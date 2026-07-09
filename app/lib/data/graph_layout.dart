import 'dart:convert';
import 'dart:math' as math;

/// Saved node positions keyed by note path, parsed from layout JSON.
Map<String, ({double x, double y})> parseLayoutPositions(String? json) {
  if (json == null || json.isEmpty) return {};
  try {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final nodes = (data['nodes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final out = <String, ({double x, double y})>{};
    for (final n in nodes) {
      final id = n['data'] as String?;
      final pos = n['position'] as Map?;
      if (id == null || pos == null) continue;
      out[id] = (
        x: (pos['x'] as num).toDouble(),
        y: (pos['y'] as num).toDouble(),
      );
    }
    return out;
  } catch (_) {
    return {};
  }
}

/// Parse persisted zoom scale from layout JSON envelope (default 1.0).
double parseLayoutScale(String? json) {
  if (json == null || json.isEmpty) return 1.0;
  try {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final scale = data['scale'];
    if (scale is num && scale > 0) {
      return scale.toDouble().clamp(0.1, 2.0);
    }
  } catch (_) {
    // fall through
  }
  return 1.0;
}

/// Merge graph controller JSON with viewport scale for persistence.
String encodeLayoutWithScale(String graphJson, double scale) {
  try {
    final data = jsonDecode(graphJson) as Map<String, dynamic>;
    data['scale'] = scale.clamp(0.1, 2.0);
    return jsonEncode(data);
  } catch (_) {
    return graphJson;
  }
}

/// Ring layout for nodes without saved positions so they are not stacked at origin.
Map<String, ({double x, double y})> initialSpreadPositions(
  List<String> ids, {
  double radius = 160,
}) {
  if (ids.isEmpty) return {};
  if (ids.length == 1) {
    return {ids.first: (x: 0.0, y: 0.0)};
  }
  final out = <String, ({double x, double y})>{};
  for (var i = 0; i < ids.length; i++) {
    final angle = 2 * math.pi * i / ids.length;
    out[ids[i]] = (
      x: radius * math.cos(angle),
      y: radius * math.sin(angle),
    );
  }
  return out;
}

/// Keep only positions for nodes that still exist in [graphData].
Map<String, ({double x, double y})> pruneLayoutPositions(
  Map<String, dynamic> graphData,
  Map<String, ({double x, double y})> positions,
) {
  final ids = {
    for (final n in (graphData['nodes'] as List).cast<Map>()) n['id'] as String,
  };
  return Map.fromEntries(
    positions.entries.where((e) => ids.contains(e.key)),
  );
}
