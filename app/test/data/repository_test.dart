import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/data/repository.dart';
import 'package:vesnai_app/data/sync_queue.dart';
import 'package:vesnai_app/data/tagging.dart';

void main() {
  test('capture saves locally with on-device tag suggestions (offline)', () async {
    final store = InMemoryNoteStore();
    final engine = SyncEngine(
      store: store,
      clientProvider: () => null,
      reachable: () => false,
    );
    final repo = NoteRepository(store: store, sync: engine, tagger: const HeuristicTagger());

    final note = await repo.capture(title: 'Great idea', body: 'what if we build it');
    expect(note.type, 'Idea');
    expect(note.tags, contains('idea'));

    final all = await repo.notes();
    expect(all.length, 1);
    expect(all.first.isPending, isTrue); // queued for sync while offline
  });
}
