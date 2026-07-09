import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:okf_dart/okf_dart.dart';
import 'package:vesnai_app/data/api_client.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/data/sync_queue.dart';
import 'package:vesnai_app/models/note.dart';

class _OfflineHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw Exception('network offline');
  }
}

/// Minimal fake of the server's /v1/sync endpoints that records pushed changes.
class _FakeSyncServer extends http.BaseClient {
  final List<Map<String, dynamic>> pushedChanges = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/v1/sync/push') {
      final body =
          jsonDecode((request as http.Request).body) as Map<String, dynamic>;
      pushedChanges.addAll(
        (body['changes'] as List).cast<Map<String, dynamic>>(),
      );
      return _json({'cursor': 1, 'applied': pushedChanges.length});
    }
    if (request.url.path == '/v1/sync/pull') {
      return _json({'cursor': 1, 'changes': []});
    }
    return http.StreamedResponse(Stream.value([]), 404);
  }

  http.StreamedResponse _json(Map<String, dynamic> payload) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(payload))),
        200,
        headers: {'content-type': 'application/json'},
      );
}

void main() {
  test('flush returns -1 when HTTP fails and keeps pending notes', () async {
    final store = InMemoryNoteStore();
    final client = VesnaiApiClient(
      baseUrl: Uri.parse('http://localhost:9999'),
      token: 'test',
      client: _OfflineHttp(),
    );
    final engine = SyncEngine(
      store: store,
      reachable: () => true,
      clientProvider: () => client,
    );
    final note = Note(
      path: 'notes/test.md',
      title: 'Test',
      body: 'body',
      syncState: SyncState.pendingCreate,
    );
    await engine.saveLocal(note);
    expect(await engine.flush(), -1);
    final listed = await store.all();
    expect(listed.length, 1);
    expect(listed.first.syncState, SyncState.pendingCreate);
  });

  test('pendingDelete notes are hidden from all()', () async {
    final store = InMemoryNoteStore();
    await store.put(const Note(path: 'notes/keep.md', title: 'Keep'));
    await store.put(const Note(
      path: 'notes/gone.md',
      title: 'Gone',
      syncState: SyncState.pendingDelete,
    ));
    final listed = await store.all();
    expect(listed.length, 1);
    expect(listed.first.path, 'notes/keep.md');
  });

  test('offline done toggle is pushed to the server once reachable', () async {
    final store = InMemoryNoteStore();
    final server = _FakeSyncServer();
    var online = false;
    final engine = SyncEngine(
      store: store,
      reachable: () => online,
      clientProvider: () => VesnaiApiClient(
        baseUrl: Uri.parse('http://localhost:9999'),
        token: 'test',
        client: server,
      ),
    );

    // Mark done while offline: stays queued locally with done intact.
    await engine.saveLocal(const Note(
      path: 'notes/shopping.md',
      title: 'Shopping',
      done: true,
      doneAt: '2026-07-08T08:00:00Z',
    ));
    expect(await engine.flush(), -1);
    final queued = await store.get('notes/shopping.md');
    expect(queued!.done, isTrue);
    expect(queued.isPending, isTrue);

    // Back online: the pushed sync doc carries vesnai.done / done_at.
    online = true;
    expect(await engine.flush(force: true), 1);
    final doc = server.pushedChanges.single['doc'] as String;
    final pushed = Note.fromConcept('notes/shopping.md', parseConcept(doc));
    expect(pushed.done, isTrue);
    expect(pushed.doneAt, '2026-07-08T08:00:00Z');
    final synced = await store.get('notes/shopping.md');
    expect(synced!.syncState, SyncState.synced);
  });

  test('bootstrap returns -1 on network failure', () async {
    final store = InMemoryNoteStore();
    final client = VesnaiApiClient(
      baseUrl: Uri.parse('http://localhost:9999'),
      token: 'test',
      client: _OfflineHttp(),
    );
    final engine = SyncEngine(
      store: store,
      reachable: () => true,
      clientProvider: () => client,
    );
    expect(await engine.bootstrap(), -1);
  });
}
