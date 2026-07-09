import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Fullscreen pinch/zoom viewer for in-app images (chat, notes).
class MediaViewerScreen extends StatelessWidget {
  final Uint8List bytes;
  final String? title;

  const MediaViewerScreen({
    super.key,
    required this.bytes,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title ?? AppLocalizations.of(context).imageLabel),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
