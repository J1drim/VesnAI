import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:vesnai_app/data/api_client.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/data/repository.dart';
import 'package:vesnai_app/data/sync_queue.dart';
import 'package:vesnai_app/data/tagging.dart';
import 'package:vesnai_app/models/note.dart';

void main() {
  test('capture returns before slow push completes', () async {
    final pushStarted = Completer<void>();
    final allowPush = Completer<void>();
    final httpClient = MockClient((request) async {
      if (request.url.path.contains('sync/push')) {
        if (!pushStarted.isCompleted) pushStarted.complete();
        await allowPush.future;
        return Response(jsonEncode({}), 200);
      }
      if (request.url.path.contains('sync/pull')) {
        return Response(jsonEncode({'cursor': 0, 'changes': []}), 200);
      }
      return Response('[]', 200);
    });

    final apiClient = VesnaiApiClient(
      baseUrl: Uri.parse('http://test'),
      token: 'tok',
      client: httpClient,
    );
    final store = InMemoryNoteStore();
    final sync = SyncEngine(
      store: store,
      clientProvider: () => apiClient,
      reachable: () => true,
    );
    final repo = NoteRepository(
      store: store,
      sync: sync,
      tagger: const HeuristicTagger(),
    );

    final sw = Stopwatch()..start();
    final note = await repo.capture(title: 'Hi', body: 'there');
    sw.stop();

    expect(sw.elapsedMilliseconds, lessThan(500));
    expect(note.title, 'Hi');
    expect(note.isPending, isTrue);
    await pushStarted.future.timeout(const Duration(seconds: 2));
    allowPush.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('flush skips retry within failure cooldown', () async {
    var calls = 0;
    final httpClient = MockClient((_) async {
      calls++;
      throw Exception('network down');
    });
    final apiClient = VesnaiApiClient(
      baseUrl: Uri.parse('http://test'),
      token: 'tok',
      client: httpClient,
    );
    final store = InMemoryNoteStore();
    await store.put(
      const Note(
        path: 'notes/x.md',
        title: 'X',
        syncState: SyncState.pendingCreate,
      ),
    );
    final sync = SyncEngine(
      store: store,
      clientProvider: () => apiClient,
      reachable: () => true,
    );

    expect(await sync.flush(), -1);
    expect(await sync.flush(), -1);
    expect(calls, 1);

    sync.resetFailureCircuit();
    expect(await sync.flush(force: true), -1);
    expect(calls, 2);
  });

  test('update bumps vesnai version for sync', () async {
    final store = InMemoryNoteStore();
    await store.put(
      const Note(path: 'notes/a.md', title: 'A', body: 'one', version: 2),
    );
    final sync = SyncEngine(
      store: store,
      clientProvider: () => null,
      reachable: () => false,
    );
    final repo = NoteRepository(
      store: store,
      sync: sync,
      tagger: const HeuristicTagger(),
    );

    await repo.update(const Note(path: 'notes/a.md', title: 'A', body: 'two', version: 2));

    final saved = await store.get('notes/a.md');
    expect(saved?.body, 'two');
    expect(saved?.version, 3);
    expect(saved?.syncState, SyncState.pendingUpdate);
  });

  test('update uses store version when UI note is stale', () async {
    final store = InMemoryNoteStore();
    await store.put(
      const Note(path: 'notes/a.md', title: 'A', body: 'one', version: 4),
    );
    final sync = SyncEngine(
      store: store,
      clientProvider: () => null,
      reachable: () => false,
    );
    final repo = NoteRepository(
      store: store,
      sync: sync,
      tagger: const HeuristicTagger(),
    );

    await repo.update(const Note(path: 'notes/a.md', title: 'A', body: 'two', version: 1));

    final saved = await store.get('notes/a.md');
    expect(saved?.version, 5);
  });
}
