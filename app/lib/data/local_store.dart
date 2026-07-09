import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:okf_dart/okf_dart.dart';

import '../models/note.dart';
import 'drift/database.dart';

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

  /// Persisted sync cursor (0 if never synced). Stored so deltas resume across
  /// restarts.
  Future<int> getCursor() async => 0;
  Future<void> setCursor(int cursor) async {}
}

class InMemoryNoteStore implements LocalNoteStore {
  final Map<String, Note> _notes = {};

  @override
  Future<List<Note>> all() async {
    final list = _notes.values
        .where((n) => n.syncState != SyncState.pendingDelete)
        .toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return list;
  }

  @override
  Future<Note?> get(String path) async => _notes[path];

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
      );

  @override
  Future<List<Note>> all() async {
    final rows = await (db.select(db.noteRows)
          ..where((t) => t.syncState.equals(SyncState.pendingDelete.index).not())
          ..orderBy([(t) => OrderingTerm.desc(t.updated)]))
        .get();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Note?> get(String path) async {
    final row = await (db.select(db.noteRows)..where((t) => t.path.equals(path)))
        .getSingleOrNull();
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
    final rows = await (db.select(db.noteRows)
          ..where((t) => t.syncState.equals(SyncState.synced.index).not()))
        .get();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<int> getCursor() async {
    final row = await (db.select(db.syncMeta)..where((t) => t.key.equals('cursor')))
        .getSingleOrNull();
    return row == null ? 0 : (int.tryParse(row.value) ?? 0);
  }

  @override
  Future<void> setCursor(int cursor) async {
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion(key: const Value('cursor'), value: Value('$cursor')),
        );
  }
}
