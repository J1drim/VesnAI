import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vesnai_app/data/api_client.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/data/sync_queue.dart';
import 'package:vesnai_app/models/note.dart';

SyncEngine _engine(InMemoryNoteStore store, http.Client client) => SyncEngine(
      store: store,
      clientProvider: () => VesnaiApiClient(
        baseUrl: Uri.parse('https://server.test'),
        token: 't',
        client: client,
      ),
      reachable: () => true,
    );

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  test('bootstrap() merges the full server catalog into the local store', () async {
    final mock = MockClient((req) async {
      switch (req.url.path) {
        case '/v1/notes':
          return _json([
            {
              'path': 'notes/idea.md',
              'title': 'My idea',
              'type': 'Idea',
              'origin': 'user',
              'version': 3,
              'updated': '2026-06-01T00:00:00Z',
            },
            {
              'path': 'generated/img.md',
              'title': 'AI image',
              'type': 'GeneratedImage',
              'origin': 'generated',
              'version': 1,
            },
          ]);
        case '/v1/sync/pull':
          return _json({'cursor': 0, 'changes': []});
      }
      return http.Response('not found', 404);
    });

    final store = InMemoryNoteStore();
    final pushed = await _engine(store, mock).bootstrap();

    expect(pushed, 0);
    final notes = await store.all();
    expect(notes.map((n) => n.path), containsAll(['notes/idea.md', 'generated/img.md']));
    final idea = notes.firstWhere((n) => n.path == 'notes/idea.md');
    expect(idea.version, 3);
    expect(idea.updated, '2026-06-01T00:00:00Z');
    final generated = notes.firstWhere((n) => n.path == 'generated/img.md');
    expect(generated.isGenerated, isTrue);
    expect(generated.syncState, SyncState.synced);
  });

  test('bootstrap() does not regress a higher local version', () async {
    final mock = MockClient((req) async {
      switch (req.url.path) {
        case '/v1/notes':
          return _json([
            {'path': 'notes/idea.md', 'title': 'Server title', 'origin': 'user', 'version': 1},
          ]);
        case '/v1/sync/pull':
          return _json({'cursor': 0, 'changes': []});
      }
      return http.Response('not found', 404);
    });

    final store = InMemoryNoteStore();
    await store.put(const Note(
      path: 'notes/idea.md',
      title: 'Synced',
      version: 5,
      updated: '2026-06-02T00:00:00Z',
    ));

    await _engine(store, mock).bootstrap();

    final note = await store.get('notes/idea.md');
    expect(note!.version, 5);
    expect(note.updated, '2026-06-02T00:00:00Z');
  });

  test('bootstrap() does not clobber a local pending edit', () async {
    final mock = MockClient((req) async {
      switch (req.url.path) {
        case '/v1/notes':
          return _json([
            {'path': 'notes/idea.md', 'title': 'Server title', 'origin': 'user'},
          ]);
        case '/v1/sync/push':
          return _json({'ok': true});
        case '/v1/sync/pull':
          return _json({'cursor': 0, 'changes': []});
      }
      return http.Response('not found', 404);
    });

    final store = InMemoryNoteStore();
    await store.put(const Note(
      path: 'notes/idea.md',
      title: 'Local edit',
      syncState: SyncState.pendingUpdate,
    ));

    await _engine(store, mock).bootstrap();

    final note = await store.get('notes/idea.md');
    expect(note!.title, 'Local edit');
    expect(note.syncState, SyncState.synced);
  });

  test('bootstrap() returns -1 when the server is unreachable', () async {
    final engine = SyncEngine(
      store: InMemoryNoteStore(),
      clientProvider: () => null,
      reachable: () => false,
    );
    expect(await engine.bootstrap(), -1);
  });
}
