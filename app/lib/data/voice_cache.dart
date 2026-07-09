import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stable short hash for TTS cache keys (FNV-1a 64-bit, first 8 hex chars).
String ttsContentHash(String content) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(content.trim())) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0').substring(0, 8);
}

/// True when [path] is a content-hash TTS file matching [content].
bool ttsPathMatchesContent(String path, String content) {
  if (path.isEmpty) return false;
  final hash = ttsContentHash(content);
  return path.contains('_$hash.');
}

/// On-disk cache for TTS audio keyed by chat message id + content hash.
class VoiceCache {
  final Directory root;

  VoiceCache(this.root);

  static Future<VoiceCache> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(dir.path, 'vesnai_voice'));
    await root.create(recursive: true);
    return VoiceCache(root);
  }

  String _safeId(String messageId) =>
      messageId.replaceAll(RegExp(r'[^\w.-]'), '_');

  File pathForMessage(String messageId, String contentHash, String ext) {
    return File(p.join(root.path, '${_safeId(messageId)}_$contentHash.$ext'));
  }

  Future<String?> existingPath(String messageId, String contentHash) async {
    for (final ext in ['wav', 'mp3']) {
      final file = pathForMessage(messageId, contentHash, ext);
      if (await file.exists()) return file.path;
    }
    return null;
  }

  Future<String> write(
    String messageId,
    String contentHash,
    Uint8List bytes,
    String ext,
  ) async {
    await deleteStaleForMessage(messageId, contentHash);
    final file = pathForMessage(messageId, contentHash, ext);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Remove cache files for [messageId] whose hash differs from [contentHash].
  Future<void> deleteStaleForMessage(String messageId, String contentHash) async {
    final prefix = '${_safeId(messageId)}_';
    final legacyPrefix = '${_safeId(messageId)}.';
    if (!await root.exists()) return;
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith(prefix) && !name.startsWith('$prefix$contentHash.')) {
        await entity.delete();
      }
      if (name.startsWith(legacyPrefix) && !name.startsWith('${legacyPrefix}_')) {
        await entity.delete();
      }
    }
  }

  Future<void> delete(String messageId) async {
    final prefix = _safeId(messageId);
    if (!await root.exists()) return;
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == '$prefix.wav' ||
          name == '$prefix.mp3' ||
          name.startsWith('${prefix}_')) {
        await entity.delete();
      }
    }
  }

  Future<void> deleteForMessages(Iterable<String> messageIds) async {
    for (final id in messageIds) {
      await delete(id);
    }
  }
}
