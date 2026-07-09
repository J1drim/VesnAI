/// Attachment metadata for a chat message (mirrors server JSON).
class ChatAttachmentMeta {
  final String path;
  final String kind;
  final String filename;
  final String mime;
  final String sessionId;

  const ChatAttachmentMeta({
    required this.path,
    required this.kind,
    required this.filename,
    this.mime = '',
    this.sessionId = '',
  });

  factory ChatAttachmentMeta.fromJson(Map<String, dynamic> j, {String sessionId = ''}) =>
      ChatAttachmentMeta(
        path: j['path'] as String,
        kind: (j['kind'] ?? 'file') as String,
        filename: (j['filename'] ?? j['path']) as String,
        mime: (j['mime'] ?? '') as String,
        sessionId: sessionId,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'kind': kind,
        'filename': filename,
        'mime': mime,
      };

  bool get isImage =>
      kind == 'image' || kind == 'generated' || mime.startsWith('image/');
  bool get isAudio => kind == 'audio' || mime.startsWith('audio/');
  bool get isDocument {
    if (kind == 'document') return true;
    final lower = filename.toLowerCase();
    return lower.endsWith('.pdf') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.pptx') ||
        mime.contains('pdf') ||
        mime.contains('wordprocessingml') ||
        mime.contains('presentationml');
  }
}

/// Local attachment waiting to upload on send.
class PendingChatAttachment {
  final String filename;
  final List<int> bytes;
  final String kind;

  const PendingChatAttachment({
    required this.filename,
    required this.bytes,
    this.kind = 'file',
  });
}
