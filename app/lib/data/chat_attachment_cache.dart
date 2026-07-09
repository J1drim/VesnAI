import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk cache for chat attachment bytes keyed by session + server path.
class ChatAttachmentCache {
  final Directory root;

  ChatAttachmentCache(this.root);

  static Future<ChatAttachmentCache> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(dir.path, 'vesnai_chat_attachments'));
    await root.create(recursive: true);
    return ChatAttachmentCache(root);
  }

  File _file(String sessionId, String path) {
    final name = p.basename(path);
    return File(p.join(root.path, sessionId, name));
  }

  Future<Uint8List?> readBytes(String sessionId, String path) async {
    final file = _file(sessionId, path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> write(String sessionId, String path, Uint8List bytes) async {
    final file = _file(sessionId, path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }
}
