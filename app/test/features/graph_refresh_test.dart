import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/graph_layout.dart';
import 'package:vesnai_app/data/local_graph.dart';
import 'package:vesnai_app/features/graph/graph_screen.dart';

void main() {
  test(
    'focus includes incoming/outgoing neighbors only and preserves hidden layout',
    () {
      final graph = {
        'nodes': [
          for (final id in ['a', 'b', 'c', 'd']) {'id': id},
        ],
        'edges': [
          {'source': 'b', 'target': 'a'},
          {'source': 'a', 'target': 'c'},
          {'source': 'c', 'target': 'd'},
        ],
      };
      final focused = graphNeighborhood(graph, 'a');
      expect((focused['nodes'] as List).map((n) => n['id']), ['a', 'b', 'c']);
      expect(focused['edges'], hasLength(2));
      final merged = mergeGraphLayout(
        '{"nodes":[{"data":"hidden","position":{"x":3,"y":4}}]}',
        '{"nodes":[{"data":"visible","position":{"x":5,"y":6}}]}',
        .8,
      );
      expect(parseLayoutPositions(merged).keys, ['hidden', 'visible']);
      expect(parseLayoutScale(merged), .8);
    },
  );
  test('groupTagsByFirstLetter buckets and sorts tags', () {
    final grouped = groupTagsByFirstLetter(['work', 'home', 'ideas', '3d']);
    expect(grouped.keys, ['#', 'H', 'I', 'W']);
    expect(grouped['H'], ['home']);
    expect(grouped['I'], ['ideas']);
    expect(grouped['W'], ['work']);
    expect(grouped['#'], ['3d']);
  });

  test('initialSpreadPositions places nodes on a ring', () {
    final spread = initialSpreadPositions(['a', 'b', 'c']);
    expect(spread.length, 3);
    expect(spread['a']!.x, closeTo(160, 0.01));
    expect(spread['a']!.y, closeTo(0, 0.01));
  });

  test('graphDataSignature includes title so renames trigger rebuild', () {
    final base = {
      'nodes': [
        {
          'id': 'notes/a.md',
          'title': 'Alpha',
          'type': 'Note',
          'origin': 'user',
        },
      ],
      'edges': [],
    };
    final renamed = {
      'nodes': [
        {'id': 'notes/a.md', 'title': 'Beta', 'type': 'Note', 'origin': 'user'},
      ],
      'edges': [],
    };

    expect(graphDataSignature(base), isNot(graphDataSignature(renamed)));
  });

  test('graphDataSignature includes edges', () {
    final noEdge = {
      'nodes': [
        {'id': 'notes/a.md', 'title': 'A', 'type': 'Note', 'origin': 'user'},
      ],
      'edges': [],
    };
    final withEdge = {
      'nodes': [
        {'id': 'notes/a.md', 'title': 'A', 'type': 'Note', 'origin': 'user'},
        {'id': 'notes/b.md', 'title': 'B', 'type': 'Note', 'origin': 'user'},
      ],
      'edges': [
        {'source': 'notes/a.md', 'target': 'notes/b.md'},
      ],
    };

    expect(graphDataSignature(noEdge), isNot(graphDataSignature(withEdge)));
  });
}
