import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/attachment_cache.dart';
import 'package:vesnai_app/data/capture_draft.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/data/repository.dart';
import 'package:vesnai_app/data/shared_capture.dart';
import 'package:vesnai_app/data/sync_queue.dart';
import 'package:vesnai_app/data/tagging.dart';
import 'package:vesnai_app/models/note.dart';

class _Bridge extends NativeShareBridge {
  final items = <Map<String, dynamic>>[];
  bool failAck = false;
  @override
  Future<List<Map<String, dynamic>>> list() async => [...items];
  @override
  Future<void> acknowledge(String id) async {
    if (failAck) throw StateError('native ack interrupted');
    items.removeWhere((item) => item['id'] == id);
  }
}

void main() {
  test(
    'offline shares preserve drafts, durable media and edited notes during replay',
    () async {
      final dir = await Directory.systemTemp.createTemp('vesnai-share-test');
      addTearDown(() => dir.delete(recursive: true));
      final store = InMemoryNoteStore();
      final drafts = CaptureDraftStore(
        store,
        AttachmentCache(Directory('${dir.path}/cache')),
      );
      await drafts.save({'title': 'Unfinished draft', 'body': 'Keep this'});
      final bridge = _Bridge();
      final sync = SyncEngine(
        store: store,
        clientProvider: () => null,
        reachable: () => false,
      );
      final repository = NoteRepository(
        store: store,
        sync: sync,
        tagger: const HeuristicTagger(),
      );
      final service = SharedCaptureService(bridge, store, drafts, repository);
      final file = File('${dir.path}/shared.pdf');
      await file.writeAsBytes([1, 2, 3]);
      bridge.items.add({
        'id': 'one',
        'text': 'https://example.com/article',
        'title': 'Article',
        'files': [
          {'name': 'shared.pdf', 'path': file.path},
        ],
      });
      bridge.failAck = true;
      await expectLater(service.ingest(), throwsStateError);
      final note = (await store.all()).single;
      expect(note.tags, ['inbox']);
      expect(note.source, 'https://example.com/article');
      expect(note.syncState, SyncState.pendingCreate);
      expect(await drafts.cache.readBytes(note.attachments.single), [1, 2, 3]);
      expect((await drafts.load())!['title'], 'Unfinished draft');
      await store.put(note.copyWith(title: 'Edited after capture'));
      await file.delete();
      bridge.failAck = false;
      await service.ingest();
      expect((await store.all()).single.title, 'Edited after capture');
      expect(bridge.items, isEmpty);
      bridge.items.add({
        'id': 'two',
        'text': 'https://example.com/article\nA different excerpt',
        'files': [],
      });
      expect(await service.ingest(), 1);
      final duplicate = await store.get('notes/shared-two.md');
      expect(
        (duplicate!.frontmatter['vesnai'] as Map)['duplicate_of'],
        note.path,
      );
      bridge.items.add({
        'id': 'three',
        'text': 'https://example.com/article\nA different excerpt',
        'files': [],
      });
      expect(await service.ingest(), 0);
      expect(await store.all(), hasLength(2));
    },
  );
}
