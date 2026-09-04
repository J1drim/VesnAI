import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vesnai_app/data/api_client.dart';
import 'package:vesnai_app/data/attachment_cache.dart';
import 'package:vesnai_app/data/capture_draft.dart';
import 'package:vesnai_app/data/drift/database.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/data/sync_queue.dart';
import 'package:vesnai_app/models/note.dart';

void main() {
  test('draft and attachment survive database and cache restart', () async {
    final dir = await Directory.systemTemp.createTemp('vesnai-draft-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/notes.sqlite');
    var db = VesnaiDatabase(NativeDatabase(file));
    var store = DriftNoteStore(db);
    var drafts = CaptureDraftStore(store, AttachmentCache(dir));
    final bytes = Uint8List.fromList([1, 2, 3]);
    final path = await drafts.persistAttachment('../../test.PDF', bytes);
    expect(path, matches(r'^attachments/[a-f0-9]{64}\.pdf$'));
    await drafts.save({
      'path': 'notes/draft.md',
      'title': 'Draft',
      'body': 'Body',
      'type': 'Idea',
      'tags': ['custom'],
      'attachments': [
        {'name': 'test.PDF', 'path': path},
      ],
    });
    await db.close();
    db = VesnaiDatabase(NativeDatabase(file));
    addTearDown(db.close);
    store = DriftNoteStore(db);
    drafts = CaptureDraftStore(store, AttachmentCache(dir));
    expect((await drafts.load())!['tags'], ['custom']);
    expect(await drafts.cache.readBytes(path), bytes);
    await drafts.releaseUnused([path]);
    expect(await drafts.cache.exists(path), isTrue); // draft owns it
    await drafts.clear();
    await drafts.releaseUnused([path]);
    expect(await drafts.cache.exists(path), isFalse);
  });

  test(
    'offline upload failure retains note; retry uploads before push',
    () async {
      final dir = await Directory.systemTemp.createTemp('vesnai-upload-test');
      addTearDown(() => dir.delete(recursive: true));
      final store = InMemoryNoteStore();
      final drafts = CaptureDraftStore(store, AttachmentCache(dir));
      final path = await drafts.persistAttachment(
        'file.txt',
        Uint8List.fromList([1, 2]),
      );
      await drafts.enqueueAttachments([path]);
      var offline = true;
      final requests = <String>[];
      final client = VesnaiApiClient(
        baseUrl: Uri.parse('http://localhost'),
        token: 't',
        client: MockClient((request) async {
          requests.add(request.url.path);
          if (offline) throw const SocketException('offline');
          if (request.url.path.endsWith('/attachments'))
            return http.Response(jsonEncode({'attachment': path}), 200);
          if (request.url.path.endsWith('/push'))
            return http.Response(
              jsonEncode({
                'cursor': 1,
                'applied': ['notes/draft.md'],
              }),
              200,
            );
          return http.Response(jsonEncode({'cursor': 1, 'changes': []}), 200);
        }),
      );
      final engine = SyncEngine(
        store: store,
        clientProvider: () => client,
        reachable: () => true,
        uploadAttachments: drafts.uploadPending,
      );
      await engine.saveLocal(
        Note(path: 'notes/draft.md', title: 'File', attachments: [path]),
      );
      expect(await engine.flush(), -1);
      expect((await store.pending()).length, 1);
      offline = false;
      requests.clear();
      expect(await engine.flush(force: true), 1);
      expect(requests.take(2), ['/v1/library/attachments', '/v1/sync/push']);
      expect(await store.pending(), isEmpty);
      await drafts.releaseUnused([path]);
      expect(await drafts.cache.exists(path), isTrue); // saved note owns it
    },
  );
}
