import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:okf_dart/okf_dart.dart';
import 'package:vesnai_app/data/api_client.dart';
import 'package:vesnai_app/data/drift/database.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/data/sync_queue.dart';
import 'package:vesnai_app/models/note.dart';

http.Response json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

SyncEngine engine(
  LocalNoteStore store,
  Future<http.Response> Function(http.Request) handler,
) => SyncEngine(
  store: store,
  reachable: () => true,
  clientProvider: () => VesnaiApiClient(
    baseUrl: Uri.parse('https://test.invalid'),
    token: 'test',
    client: MockClient(handler),
  ),
);

class FailingStore extends InMemoryNoteStore {
  @override
  Future<void> put(Note note) async {
    if (note.path == 'notes/fail.md') throw StateError('disk failed');
    return super.put(note);
  }
}

void main() {
  test(
    'older upload cannot acknowledge newer edit; overlapping flushes serialize',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final store = InMemoryNoteStore();
      var pushes = 0;
      final e = engine(store, (request) async {
        if (request.url.path.endsWith('/push')) {
          pushes++;
          if (pushes == 1) {
            started.complete();
            await release.future;
          }
          final change = (jsonDecode(request.body)['changes'] as List).single;
          expect(change['base_version'], pushes == 1 ? 0 : 1);
          return json({
            'applied': ['notes/a.md'],
            'versions': {'notes/a.md': pushes},
          });
        }
        return json({'cursor': 1, 'changes': []});
      });
      await e.saveLocal(const Note(path: 'notes/a.md', body: 'first'));
      final flush = e.flush();
      await started.future;
      await e.saveLocal(
        const Note(path: 'notes/a.md', body: 'new edit', version: 2),
      );
      final second = e.flush();
      expect(pushes, 1);
      release.complete();
      expect(await flush, 1);
      expect(await second, 1);
      expect((await store.get('notes/a.md'))!.body, 'new edit');
      expect((await store.get('notes/a.md'))!.baseVersion, 2);
      expect((await store.pending()), isEmpty);
    },
  );

  test('only individually acknowledged notes become synced', () async {
    final store = InMemoryNoteStore();
    final e = engine(
      store,
      (request) async => json(
        request.url.path.endsWith('/push')
            ? {
                'applied': ['notes/a.md'],
              }
            : {'cursor': 1, 'changes': []},
      ),
    );
    await e.saveLocal(const Note(path: 'notes/a.md'));
    await e.saveLocal(const Note(path: 'notes/b.md', body: 'unacknowledged'));
    expect(await e.flush(), 1);
    expect((await store.get('notes/a.md'))!.isPending, false);
    expect((await store.get('notes/b.md'))!.isPending, true);
    expect((await store.get('notes/b.md'))!.syncError, isNotEmpty);
  });

  test('failed pull rolls back changes and cursor together', () async {
    final store = FailingStore();
    await store.setCursor(7);
    final e = engine(
      store,
      (_) async => json({
        'cursor': 9,
        'changes': [
          for (final path in ['notes/a.md', 'notes/fail.md'])
            {'path': path, 'doc': dumpConcept(Note(path: path).toConcept())},
        ],
      }),
    );
    expect(await e.flush(), -1);
    expect(await store.all(), isEmpty);
    expect(await store.getCursor(), 7);
  });

  test(
    'deletion conflict survives and keep mine queues a versioned deletion',
    () async {
      final store = InMemoryNoteStore();
      final e = engine(store, (request) async {
        if (request.url.path == '/v1/notes')
          return json([
            {'path': 'notes/a.md', 'version': 3},
          ]);
        if (request.url.path.endsWith('/push'))
          return json({
            'applied': [],
            'conflicts': [
              {
                'path': 'notes/a.md',
                'server_version': 3,
                'error': 'note changed before deletion',
              },
            ],
          });
        return json({'cursor': 1, 'changes': []});
      });
      await store.put(const Note(path: 'notes/a.md', baseVersion: 2));
      await e.deleteLocal('notes/a.md');
      await e.flush();
      expect((await store.get('notes/a.md'))!.conflictDeleted, true);
      await e.resolveConflict('notes/a.md', 'mine');
      final note = (await store.get('notes/a.md'))!;
      expect(note.syncState, SyncState.pendingDelete);
      expect(note.baseVersion, 3);
    },
  );

  test('Drift persists metadata and rolls back a transaction', () async {
    final db = VesnaiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DriftNoteStore(db);
    final note = Note.fromConcept(
      'notes/a.md',
      parseConcept(
        '---\ntitle: A\ncustom: [one, two]\nvesnai:\n  id: permanent\n  created: original\n  version: 4\n  pinned: true\n---\nbody',
      ),
    );
    await store.put(
      note.copyWith(
        body: 'edited',
        syncState: SyncState.conflict,
        conflictDeleted: true,
      ),
    );
    final loaded = (await store.get(note.path))!;
    expect(loaded.toConcept().frontmatter['custom'], ['one', 'two']);
    expect(loaded.toConcept().vesnai['id'], 'permanent');
    expect(loaded.pinned, true);
    expect(loaded.conflictDeleted, true);
    expect(loaded.baseVersion, 4);
    await expectLater(
      store.transaction(() async {
        await store.remove(note.path);
        await store.setCursor(10);
        throw StateError('interrupted');
      }),
      throwsStateError,
    );
    expect(await store.get(note.path), isNotNull);
    expect(await store.getCursor(), 0);
  });
}
