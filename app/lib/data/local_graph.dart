import 'package:okf_dart/okf_dart.dart';

import '../features/notes/note_type_ui.dart';
import '../models/note.dart';

/// Build a knowledge graph from the local note mirror (mirrors server graph.py).
///
/// The Flutter app derives the graph entirely on-device from the SQLite mirror;
/// the server `/v1/graph` endpoint is not used by the client.
Map<String, dynamic> buildLocalGraph(
  List<Note> notes, {
  String? origin,
  String? type,
  String? tag,
  Set<String>? tags,
}) {
  final tagSet = {...?tags};
  if (tag != null) tagSet.add(tag);

  bool keep(Note n) {
    if (tagSet.isNotEmpty && !tagSet.any(n.tags.contains)) return false;
    if (type != null && n.type != type) return false;
    if (origin != null) {
      final o = n.origin == Origin.generated ? 'generated' : 'user';
      if (o != origin) return false;
    }
    return true;
  }

  final selected = {for (final n in notes.where(keep)) n.path: n};
  final known = selected.keys.toSet();

  final nodes = selected.entries
      .map((e) => {
            'id': e.key,
            'title': e.value.title.isEmpty ? e.key : e.value.title,
            'type': normalizeNoteType(e.value.type),
            'origin': e.value.origin == Origin.generated ? 'generated' : 'user',
            'tags': e.value.tags,
          })
      .toList();

  final edges = <Map<String, String>>[];
  final seen = <String>{};
  for (final entry in selected.entries) {
    final rel = entry.key;
    final concept = entry.value.toConcept();
    final candidates = [
      ...concept.explicitLinks().map((h) => (h, true)),
      ...concept.bodyLinks().map((h) => (h, false)),
    ];
    for (final (href, explicit) in candidates) {
      if (href.contains('://')) continue;
      final target = resolveLink(rel, href, explicit);
      final key = '$rel|$target';
      if (target != rel && known.contains(target) && !seen.contains(key)) {
        seen.add(key);
        edges.add({'source': rel, 'target': target});
      }
    }
  }

  return {'nodes': nodes, 'edges': edges};
}

/// Fingerprint of graph structure + node metadata for layout rebuild decisions.
String graphDataSignature(Map<String, dynamic> data) {
  final nodes = (data['nodes'] as List).cast<Map>();
  final edges = (data['edges'] as List).cast<Map>();
  final nodePart = nodes
      .map((n) => '${n['id']}:${n['title']}:${n['type']}:${n['origin']}')
      .join(',');
  final edgePart = edges.map((e) => '${e['source']}>${e['target']}').join(',');
  return '$nodePart|$edgePart';
}
