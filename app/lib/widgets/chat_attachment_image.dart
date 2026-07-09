import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/chat_attachment.dart';
import '../data/chat_attachment_cache.dart';

/// Loads a chat attachment: local cache first, then authenticated download.
class ChatAttachmentImage extends StatefulWidget {
  final String sessionId;
  final ChatAttachmentMeta attachment;
  final VesnaiApiClient? client;
  final ChatAttachmentCache? cache;
  final BoxFit fit;
  final double? height;
  final double? width;
  final VoidCallback? onTap;

  const ChatAttachmentImage({
    super.key,
    required this.sessionId,
    required this.attachment,
    this.client,
    this.cache,
    this.fit = BoxFit.cover,
    this.height,
    this.width,
    this.onTap,
  });

  @override
  State<ChatAttachmentImage> createState() => _ChatAttachmentImageState();
}

class _ChatAttachmentImageState extends State<ChatAttachmentImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ChatAttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.path != widget.attachment.path ||
        oldWidget.sessionId != widget.sessionId) {
      _load();
    }
  }

  Future<void> _load() async {
    final cached = widget.cache;
    if (cached != null) {
      final local = await cached.readBytes(widget.sessionId, widget.attachment.path);
      if (local != null && mounted) {
        setState(() => _bytes = local);
        return;
      }
    }
    final client = widget.client;
    if (client == null) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final data = await client.downloadChatAttachment(
        widget.sessionId,
        widget.attachment.path,
      );
      await cached?.write(widget.sessionId, widget.attachment.path, data);
      if (mounted) setState(() => _bytes = data);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_bytes != null) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _bytes!,
          fit: widget.fit,
          height: widget.height,
          width: widget.width,
        ),
      );
    } else if (_failed) {
      child = SizedBox(
        height: widget.height ?? 120,
        width: widget.width ?? 120,
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      );
    } else {
      child = SizedBox(
        height: widget.height ?? 120,
        width: widget.width ?? 120,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (widget.onTap != null && _bytes != null) {
      return GestureDetector(onTap: widget.onTap, child: child);
    }
    return child;
  }
}
