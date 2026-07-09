import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';

/// On-disk cache for note attachment bytes keyed by server-relative path.
class AttachmentCache {
  final Directory root;

  AttachmentCache(this.root);

  static Future<AttachmentCache> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(dir.path, 'vesnai_attachments'));
    await root.create(recursive: true);
    return AttachmentCache(root);
  }

  /// Collect attachment paths referenced by [note] (frontmatter + markdown body).
  static List<String> pathsFromNote(Note note) {
    final paths = <String>{...note.attachments};
    for (final m in RegExp(r'attachments/[^)\s]+').allMatches(note.body)) {
      paths.add(m.group(0)!);
    }
    return paths.toList();
  }

  File localFile(String relPath) {
    final normalized = p.normalize(relPath);
    if (normalized.startsWith('..') || p.isAbsolute(normalized)) {
      throw ArgumentError('Invalid attachment path: $relPath');
    }
    return File(p.join(root.path, normalized));
  }

  Future<bool> exists(String relPath) async => localFile(relPath).exists();

  Future<Uint8List?> readBytes(String relPath) async {
    final file = localFile(relPath);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> write(String relPath, Uint8List bytes) async {
    final file = localFile(relPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  Future<void> delete(String relPath) async {
    final file = localFile(relPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Return cached bytes, or fetch via [fetch], persist, and return.
  Future<Uint8List?> getOrFetch(
    String relPath,
    Future<Uint8List?> Function() fetch,
  ) async {
    final cached = await readBytes(relPath);
    if (cached != null) return cached;
    final bytes = await fetch();
    if (bytes == null || bytes.isEmpty) return null;
    await write(relPath, bytes);
    return bytes;
  }
}
