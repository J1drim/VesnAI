import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/attachment_cache.dart';
import '../data/chat_attachment_cache.dart';
import '../data/chat_attachment.dart';
import 'authenticated_image.dart';
import 'chat_attachment_image.dart';

/// Renders a markdown image URI from note bodies (attachments, chat, http).
class NoteAttachmentImage extends StatelessWidget {
  const NoteAttachmentImage({
    super.key,
    required this.uri,
    this.alt,
    this.client,
    required this.cache,
    required this.chatCache,
    this.maxHeight = 240,
  });

  final String uri;
  final String? alt;
  final VesnaiApiClient? client;
  final AttachmentCache cache;
  final ChatAttachmentCache chatCache;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return _fallback(context);
    final raw = parsed.toString();
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Image.network(
          raw,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => _fallback(context),
        ),
      );
    }
    if (raw.startsWith('chat:')) {
      final rest = raw.substring(5);
      final slash = rest.indexOf('/');
      if (slash > 0) {
        final sessionId = rest.substring(0, slash);
        final filename = rest.substring(slash + 1);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ChatAttachmentImage(
            sessionId: sessionId,
            attachment: ChatAttachmentMeta(
              path: filename,
              kind: 'generated',
              filename: filename,
              sessionId: sessionId,
            ),
            client: client,
            cache: chatCache,
          ),
        );
      }
      return _fallback(context);
    }
    final idx = raw.indexOf('attachments/');
    if (idx == -1) return _fallback(context);
    final rel = raw.substring(idx);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: AuthenticatedImage(
        relPath: rel,
        cache: cache,
        client: client,
        error: _fallback(context),
      ),
    );
  }

  Widget _fallback(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.broken_image_outlined, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text(alt?.isNotEmpty == true ? alt! : 'image')),
          ],
        ),
      );
}
