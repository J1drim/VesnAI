import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/app_localizations.dart';

/// A minimal freehand drawing canvas. Pops with PNG bytes (or null if cancelled)
/// so the capture flow can attach the sketch to a note.
class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key});

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> {
  final _boundaryKey = GlobalKey();
  final List<List<Offset>> _strokes = [];

  Future<void> _export() async {
    final boundary =
        _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.of(context).pop<Uint8List>(byteData?.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.draw),
        actions: [
          IconButton(
            tooltip: l.clear,
            icon: const Icon(Icons.clear),
            onPressed: () => setState(_strokes.clear),
          ),
          IconButton(
            key: const Key('draw-done'),
            tooltip: l.attach,
            icon: const Icon(Icons.check),
            onPressed: _strokes.isEmpty ? null : _export,
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _boundaryKey,
        child: GestureDetector(
          onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
          onPanUpdate: (d) => setState(() {
            if (_strokes.isNotEmpty) _strokes.last.add(d.localPosition);
          }),
          child: Container(
            color: Colors.white,
            width: double.infinity,
            height: double.infinity,
            child: CustomPaint(painter: _SketchPainter(_strokes)),
          ),
        ),
      ),
    );
  }
}

class _SketchPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SketchPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter old) => true;
}
