import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:okf_dart/okf_dart.dart';

import '../models/note.dart';
import 'api_client.dart';
import 'attachment_cache.dart';
import 'local_store.dart';

String attachmentContentPath(String name, Uint8List bytes) {
  final ext =
      RegExp(r'\.[a-z0-9]{1,10}$').firstMatch(name.toLowerCase())?.group(0) ??
      '.bin';
  return 'attachments/${sha256.convert(bytes)}$ext';
}

/// Small draft metadata lives in SQLite; media lives in the durable local cache.
class CaptureDraftStore {
  final LocalNoteStore store;
  final AttachmentCache cache;
  CaptureDraftStore(this.store, this.cache);

  Future<Map<String, dynamic>?> load() async {
    final raw = await store.localValue('capture_draft');
    return raw == null
        ? null
        : (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  Future<void> save(Map<String, dynamic> value) => store.transaction(
    () => store.setLocalValue('capture_draft', jsonEncode(value)),
  );
  Future<void> clear() =>
      store.transaction(() => store.setLocalValue('capture_draft', null));

  /// Only remove media belonging to this draft, never cached library media.
  Future<void> releaseUnused(Iterable<String> candidates) async {
    final draft = await load();
    final referenced = [
      ...await store.all(),
      ...await store.pending(),
    ].expand(AttachmentCache.pathsFromNote).toSet();
    for (final item in draft?['attachments'] as List? ?? []) {
      referenced.add(item['path'] as String);
    }
    for (final item
        in jsonDecode(await store.localValue('local_trash') ?? '[]') as List) {
      referenced.addAll(
        AttachmentCache.pathsFromNote(
          Note.fromConcept(
            item['path'] as String,
            parseConcept(item['doc'] as String),
          ),
        ),
      );
    }
    for (final path in candidates.where((p) => !referenced.contains(p))) {
      // Unsent media may belong to an in-flight capture; preserve it.
      if (!(await _uploads()).contains(path)) await cache.delete(path);
    }
  }

  Future<String> persistAttachment(String name, Uint8List bytes) async {
    final path = attachmentContentPath(name, bytes);
    if (!await cache.exists(path)) await cache.write(path, bytes);
    return path;
  }

  Future<void> enqueueAttachments(Iterable<String> paths) =>
      store.transaction(() async {
        final queued = await _uploads();
        await store.setLocalValue(
          'attachment_uploads',
          jsonEncode({...queued, ...paths}.toList()),
        );
      });

  Future<Set<String>> _uploads() async =>
      ((jsonDecode(await store.localValue('attachment_uploads') ?? '[]'))
              as List)
          .cast<String>()
          .toSet();

  Future<void> uploadPending(VesnaiApiClient client, List<Note> notes) async {
    final referenced = notes
        .where((n) => n.syncState != SyncState.pendingDelete)
        .expand(AttachmentCache.pathsFromNote)
        .toSet();
    for (final path in (await _uploads()).where(referenced.contains)) {
      final bytes = await cache.readBytes(path);
      if (bytes == null)
        throw StateError('Pending attachment is missing locally');
      final uploaded = await client.uploadLibraryAttachment(
        path.split('/').last,
        bytes,
      );
      if (uploaded != path)
        throw StateError('Attachment content identity mismatch');
      await store.transaction(() async {
        final remaining = (await _uploads())..remove(path);
        await store.setLocalValue(
          'attachment_uploads',
          jsonEncode(remaining.toList()),
        );
      });
    }
  }
}
