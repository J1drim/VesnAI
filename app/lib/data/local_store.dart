import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:okf_dart/okf_dart.dart';

import '../models/note.dart';
import 'drift/database.dart';
import 'note_filter.dart';

/// Treat user text as literal Unicode words, never as executable FTS syntax.
List<String> searchTerms(String query) => RegExp(
  r'[\p{L}\p{N}_]+',
  unicode: true,
).allMatches(query.toLowerCase()).map((m) => m.group(0)!).take(24).toList();

/// Local mirror of notes. The production implementation is backed by Drift
/// (SQLite); this interface keeps it mockable, and [InMemoryNoteStore] powers
/// tests and the first-run experience. The mirror is always rebuildable from
/// the server's OKF bundle, so it is never the source of truth.
abstract class LocalNoteStore {
  Future<List<Note>> all();
  Future<Note?> get(String path);
  Future<void> put(Note note);
  Future<void> remove(String path);
  Future<List<Note>> pending();
  Future<List<Note>> search(
    String query, {
    int limit = 100,
    int offset = 0,
    NoteFilter filter = const NoteFilter(),
  });
  Future<T> transaction<T>(Future<T> Function() action);
  Future<String?> localValue(String key);
  Future<void> setLocalValue(String key, String? value);

  /// Persisted sync cursor (0 if never synced). Stored so deltas resume across
  /// restarts.
  Future<int> getCursor() async => 0;
  Future<void> setCursor(int cursor) async {}
}

class InMemoryNoteStore implements LocalNoteStore {
  final Map<String, Note> _notes = {};
  final Map<String, String> _values = {};

  @override
  Future<String?> localValue(String key) async => _values[key];
  @override
  Future<void> setLocalValue(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  Future<void> _transactions = Future.value();

  @override
  Future<T> transaction<T>(Future<T> Function() action) {
    final result = _transactions.then((_) async {
      final before = Map<String, Note>.from(_notes);
      final beforeCursor = _cursor;
      final beforeValues = Map<String, String>.from(_values);
      try {
        return await action();
      } catch (_) {
        _notes
          ..clear()
          ..addAll(before);
        _cursor = beforeCursor;
        _values
          ..clear()
          ..addAll(beforeValues);
        rethrow;
      }
    });
    _transactions = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  @override
  Future<List<Note>> all() async {
    final list =
        _notes.values
            .where((n) => n.syncState != SyncState.pendingDelete)
            .toList()
          ..sort((a, b) => b.updated.compareTo(a.updated));
    return list;
  }

  @override
  Future<Note?> get(String path) async => _notes[path];

  @override
  Future<List<Note>> search(
    String query, {
    int limit = 100,
    int offset = 0,
    NoteFilter filter = const NoteFilter(),
  }) async {
    final terms = searchTerms(query);
    final notes = (await all())
        .where(filter.matches)
        .where(
          (n) => terms.every(
            (t) => '${n.title} ${n.tags.join(' ')} ${n.body}'
                .toLowerCase()
                .contains(t),
          ),
        )
        .toList();
    int score(Note n) => terms.fold(
      0,
      (value, t) =>
          value +
          (n.title.toLowerCase().contains(t) ? 5 : 0) +
          (n.tags.any((tag) => tag.toLowerCase().contains(t)) ? 3 : 0),
    );
    notes.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if (filter.sort == 'title') return a.title.compareTo(b.title);
      if (filter.sort == 'oldest') return a.updated.compareTo(b.updated);
      if (filter.sort == 'relevance' && terms.isNotEmpty)
        return score(b).compareTo(score(a));
      return b.updated.compareTo(a.updated);
    });
    return notes.skip(offset).take(limit).toList();
  }

  @override
  Future<void> put(Note note) async => _notes[note.path] = note;

  @override
  Future<void> remove(String path) async => _notes.remove(path);

  @override
  Future<List<Note>> pending() async =>
      _notes.values.where((n) => n.isPending).toList();

  int _cursor = 0;
  @override
  Future<int> getCursor() async => _cursor;
  @override
  Future<void> setCursor(int cursor) async => _cursor = cursor;
}

/// Drift/SQLite-backed mirror used at runtime on device.
class DriftNoteStore implements LocalNoteStore {
  final VesnaiDatabase db;

  DriftNoteStore([VesnaiDatabase? db]) : db = db ?? VesnaiDatabase();

  @override
  Future<String?> localValue(String key) async => (await (db.select(
    db.syncMeta,
  )..where((t) => t.key.equals('local:$key'))).getSingleOrNull())?.value;

  @override
  Future<void> setLocalValue(String key, String? value) async {
    if (value == null) {
      await (db.delete(
        db.syncMeta,
      )..where((t) => t.key.equals('local:$key'))).go();
    } else {
      await db
          .into(db.syncMeta)
          .insertOnConflictUpdate(
            SyncMetaCompanion(key: Value('local:$key'), value: Value(value)),
          );
    }
  }

  @override
  Future<List<Note>> search(
    String query, {
    int limit = 100,
    int offset = 0,
    NoteFilter filter = const NoteFilter(),
  }) async {
    final terms = searchTerms(query);
    final match = terms
        .map((term) => '"${term.replaceAll('"', '""')}"*')
        .join(' AND ');
    final where = <String>['n.sync_state != ?'];
    final variables = <Variable>[Variable<int>(SyncState.pendingDelete.index)];
    if (filter.libraryOnly) {
      where.add(
        "n.path NOT LIKE '%.conflict-%' AND n.type != 'ChatTranscript' AND NOT (n.source != '' AND n.type IN ('GeneratedImage','GeneratedCaption'))",
      );
    }
    if (terms.isNotEmpty) {
      where.add('note_search MATCH ?');
      variables.add(Variable<String>(match));
    }
    if (filter.scope != 'all') {
      where.add(
        "coalesce(json_extract(n.frontmatter_json, '\$.vesnai.archived'),0)=?",
      );
      variables.add(Variable<int>(filter.scope == 'archive' ? 1 : 0));
    }
    if (filter.scope == 'pinned')
      where.add("json_extract(n.frontmatter_json, '\$.vesnai.pinned')=1");
    if (!filter.showDone) where.add('n.done=0');
    if (filter.tag.isNotEmpty) {
      where.add('EXISTS (SELECT 1 FROM json_each(n.tags_json) WHERE value=?)');
      variables.add(Variable<String>(filter.tag));
    }
    if (filter.types.isNotEmpty) {
      where.add('n.type IN (${filter.types.map((_) => '?').join(',')})');
      variables.addAll(filter.types.map(Variable<String>.new));
    }
    final order = filter.sort == 'title'
        ? 'n.title COLLATE NOCASE'
        : filter.sort == 'oldest'
        ? 'n.updated ASC'
        : filter.sort == 'relevance' && terms.isNotEmpty
        ? 'bm25(note_search, 0, 5, 3, 1)'
        : 'n.updated DESC';
    final rows = await db
        .customSelect(
          '''SELECT n.* FROM note_rows n
      ${terms.isEmpty ? '' : 'JOIN note_search ON note_search.rowid=n.rowid'}
      WHERE ${where.join(' AND ')}
      ORDER BY coalesce(json_extract(n.frontmatter_json, '\$.vesnai.pinned'),0) DESC, $order, n.path LIMIT ? OFFSET ?''',
          variables: [
            ...variables,
            Variable<int>(limit),
            Variable<int>(offset),
          ],
          readsFrom: {db.noteRows},
        )
        .get();
    return rows.map((r) => _fromRow(db.noteRows.map(r.data))).toList();
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      db.transaction(action);

  Note _fromRow(NoteRow r) => Note(
    path: r.path,
    title: r.title,
    body: r.body,
    type: r.type,
    tags: (jsonDecode(r.tagsJson) as List).map((e) => e.toString()).toList(),
    origin: r.origin == 'generated' ? Origin.generated : Origin.user,
    links: (jsonDecode(r.linksJson) as List).map((e) => e.toString()).toList(),
    attachments: (jsonDecode(r.attachmentsJson) as List)
        .map((e) => e.toString())
        .toList(),
    source: r.source,
    updated: r.updated,
    version: r.version,
    done: r.done,
    doneAt: r.doneAt,
    syncState: SyncState.values[r.syncState],
    frontmatter: (jsonDecode(r.frontmatterJson) as Map).cast<String, dynamic>(),
    baseVersion: r.baseVersion,
    syncError: r.syncError,
    serverDoc: r.serverDoc,
    serverVersion: r.serverVersion,
    conflictDeleted: r.conflictDeleted,
  );

  NoteRowsCompanion _toCompanion(Note n) => NoteRowsCompanion(
    path: Value(n.path),
    title: Value(n.title),
    body: Value(n.body),
    type: Value(n.type),
    tagsJson: Value(jsonEncode(n.tags)),
    origin: Value(n.origin == Origin.generated ? 'generated' : 'user'),
    linksJson: Value(jsonEncode(n.links)),
    attachmentsJson: Value(jsonEncode(n.attachments)),
    source: Value(n.source),
    updated: Value(n.updated),
    version: Value(n.version),
    done: Value(n.done),
    doneAt: Value(n.doneAt),
    syncState: Value(n.syncState.index),
    frontmatterJson: Value(jsonEncode(n.frontmatter)),
    baseVersion: Value(n.baseVersion),
    syncError: Value(n.syncError),
    serverDoc: Value(n.serverDoc),
    serverVersion: Value(n.serverVersion),
    conflictDeleted: Value(n.conflictDeleted),
  );

  @override
  Future<List<Note>> all() async {
    final rows =
        await (db.select(db.noteRows)
              ..where(
                (t) => t.syncState.equals(SyncState.pendingDelete.index).not(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.updated)]))
            .get();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Note?> get(String path) async {
    final row = await (db.select(
      db.noteRows,
    )..where((t) => t.path.equals(path))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<void> put(Note note) async =>
      db.into(db.noteRows).insertOnConflictUpdate(_toCompanion(note));

  @override
  Future<void> remove(String path) async =>
      (db.delete(db.noteRows)..where((t) => t.path.equals(path))).go();

  @override
  Future<List<Note>> pending() async {
    final rows = await (db.select(
      db.noteRows,
    )..where((t) => t.syncState.equals(SyncState.synced.index).not())).get();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<int> getCursor() async {
    final row = await (db.select(
      db.syncMeta,
    )..where((t) => t.key.equals('cursor'))).getSingleOrNull();
    return row == null ? 0 : (int.tryParse(row.value) ?? 0);
  }

  @override
  Future<void> setCursor(int cursor) async {
    await db
        .into(db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion(
            key: const Value('cursor'),
            value: Value('$cursor'),
          ),
        );
  }
}
