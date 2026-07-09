import '../../models/note.dart';

/// Strip markdown image lines for list previews; summarize attachments.
String notePreviewBody(Note note) {
  final attachmentCount = note.attachments.length;
  final lines = note.body.split('\n');
  final textLines = <String>[];
  var imageLines = 0;
  for (final line in lines) {
    final trimmed = line.trim();
    if (RegExp(r'^!\[[^\]]*\]\([^)]+\)$').hasMatch(trimmed)) {
      imageLines++;
      continue;
    }
    if (trimmed.isNotEmpty) textLines.add(trimmed);
  }

  if (textLines.isNotEmpty) {
    return textLines.join('\n');
  }
  if (attachmentCount > 0 || imageLines > 0) {
    final n = attachmentCount > 0 ? attachmentCount : imageLines;
    return n == 1 ? 'Photo attached' : '$n attachments';
  }
  return '';
}

/// Hide auto-enrichment children, sync conflict copies, and chat transcripts.
bool noteVisibleInMainList(Note note) {
  if (note.path.contains('.conflict-')) {
    return false;
  }
  if (note.type == 'ChatTranscript') {
    return false;
  }
  if (note.source.isNotEmpty &&
      (note.type == 'GeneratedImage' || note.type == 'GeneratedCaption')) {
    return false;
  }
  return true;
}
