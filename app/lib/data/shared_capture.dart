import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../models/note.dart';
import 'capture_draft.dart';
import 'local_store.dart';
import 'repository.dart';

class NativeShareBridge {
  static const channel = MethodChannel('vesnai/shares');
  bool get supported => Platform.isAndroid || Platform.isIOS;
  Future<List<Map<String, dynamic>>> list() async {
    if (!Platform.isAndroid && !Platform.isIOS) return [];
    final raw = await channel.invokeMethod<String>('list') ?? '[]';
    return (jsonDecode(raw) as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<void> acknowledge(String id) => channel.invokeMethod<void>('ack', id);
}

String sharedSource(String text) {
  final match = RegExp(r'https?://[^\s<>]+').firstMatch(text);
  final uri = Uri.tryParse(match?.group(0) ?? '');
  if (uri == null || !uri.hasAuthority) return '';
  return uri.removeFragment().toString();
}

/// Native files are acknowledged only after local note/media durability.
/// The capture draft is independent and never overwritten by an incoming share.
class SharedCaptureService {
  final NativeShareBridge bridge;
  final LocalNoteStore store;
  final CaptureDraftStore drafts;
  final NoteRepository repository;
  bool _running = false;
  bool get running => _running;
  SharedCaptureService(this.bridge, this.store, this.drafts, this.repository);

  Future<int> ingest() async {
    if (_running) return 0;
    _running = true;
    var count = 0;
    try {
      for (final item in await bridge.list()) {
        final id = item['id'] as String;
        if (!RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(id))
          throw StateError('Invalid shared item');
        final path = 'notes/shared-$id.md';
        // Replay after a successful note save must not rewrite subsequent edits.
        if (await store.get(path) != null) {
          await bridge.acknowledge(id);
          continue;
        }
        final text = item['text'] as String? ?? '';
        if (text.length > 1000000) throw StateError('Shared text exceeds 1 MB');
        final files = item['files'] as List? ?? [];
        if (files.isEmpty && text.trim().isEmpty)
          throw StateError('Shared item is empty');
        if (files.length > 10) throw StateError('Too many shared files');
        final attachments = <String>[];
        final parts = <String>[text];
        var size = 0;
        for (final file in files) {
          final sourceFile = File(file['path'] as String);
          size += await sourceFile.length();
          if (size > 50 * 1024 * 1024)
            throw StateError('Shared files exceed 50 MB');
          final name = file['name'] as String;
          final attachment = await drafts.persistAttachment(
            name,
            await sourceFile.readAsBytes(),
          );
          attachments.add(attachment);
          final label = name.replaceAll(RegExp(r'[\[\]()\n\r]'), '_');
          final image = RegExp(
            r'\.(png|jpe?g|gif|webp)$',
            caseSensitive: false,
          ).hasMatch(name);
          parts.add('${image ? '!' : ''}[$label]($attachment)');
        }
        final source = sharedSource(text);
        final fingerprint = sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  text.trim(),
                  [...attachments]..sort(),
                ]),
              ),
            )
            .toString();
        final notes = await store.all();
        final identical = notes
            .where(
              (note) =>
                  (note.frontmatter['vesnai'] as Map?)?['share_hash'] ==
                  fingerprint,
            )
            .firstOrNull;
        if (identical != null) {
          await bridge.acknowledge(id);
          continue;
        }
        final duplicate = source.isEmpty
            ? null
            : notes.where((note) => note.source == source).firstOrNull;
        await drafts.enqueueAttachments(attachments);
        final suppliedTitle = (item['title'] as String? ?? '').trim();
        final title = suppliedTitle.isNotEmpty
            ? suppliedTitle
            : text.trim().isNotEmpty
            ? text.trim().split('\n').first
            : files.firstOrNull?['name'] as String? ?? 'Shared item';
        await repository.update(
          Note(
            path: path,
            title: title.length > 240 ? title.substring(0, 240) : title,
            body: parts.where((part) => part.isNotEmpty).join('\n\n'),
            tags: const ['inbox'],
            attachments: attachments,
            source: source,
            frontmatter: {
              'vesnai': {
                'share_hash': fingerprint,
                if (duplicate != null) 'duplicate_of': duplicate.path,
              },
            },
          ),
        );
        await bridge.acknowledge(id);
        count++;
      }
      return count;
    } finally {
      _running = false;
    }
  }
}
