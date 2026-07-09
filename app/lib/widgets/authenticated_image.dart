import 'dart:io';

import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/attachment_cache.dart';

/// Loads a note attachment: disk cache first, then authenticated network fetch.
class AuthenticatedImage extends StatefulWidget {
  final String relPath;
  final AttachmentCache cache;
  final VesnaiApiClient? client;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? error;

  const AuthenticatedImage({
    super.key,
    required this.relPath,
    required this.cache,
    this.client,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.error,
  });

  @override
  State<AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends State<AuthenticatedImage> {
  late Future<File?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relPath != widget.relPath) {
      _future = _load();
    }
  }

  Future<File?> _load() async {
    final cached = widget.cache.localFile(widget.relPath);
    if (await cached.exists()) return cached;

    final client = widget.client;
    if (client == null) return null;

    final bytes = await widget.cache.getOrFetch(
      widget.relPath,
      () async => client.downloadAttachment(widget.relPath),
    );
    if (bytes == null) return null;
    return widget.cache.localFile(widget.relPath);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return widget.placeholder ??
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
        }
        final file = snap.data;
        if (file == null || !file.existsSync()) {
          return widget.error ?? const Icon(Icons.broken_image_outlined);
        }
        return Image.file(file, fit: widget.fit);
      },
    );
  }
}
