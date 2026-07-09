import 'package:flutter_test/flutter_test.dart';
import 'package:okf_dart/okf_dart.dart';
import 'package:vesnai_app/data/graph_layout.dart';
import 'package:vesnai_app/data/graph_layout_store.dart';
import 'package:vesnai_app/features/notes/note_type_ui.dart';
import 'package:vesnai_app/models/note.dart';

void main() {
  group('parseLayoutPositions', () {
    test('returns empty map for null or invalid json', () {
      expect(parseLayoutPositions(null), isEmpty);
      expect(parseLayoutPositions('not-json'), isEmpty);
    });

    test('parses node positions from layout json', () {
      const json = '''
      {"nodes":[{"data":"notes/a.md","position":{"x":10,"y":20}}],"edges":[]}
      ''';
      final positions = parseLayoutPositions(json);
      expect(positions['notes/a.md'], (x: 10.0, y: 20.0));
    });
  });

  group('pruneLayoutPositions', () {
    test('drops positions for removed nodes', () {
      final graphData = {
        'nodes': [
          {'id': 'notes/a.md'},
        ],
        'edges': [],
      };
      final positions = {
        'notes/a.md': (x: 1.0, y: 2.0),
        'notes/removed.md': (x: 3.0, y: 4.0),
      };
      final pruned = pruneLayoutPositions(graphData, positions);
      expect(pruned.keys, ['notes/a.md']);
      expect(pruned['notes/a.md'], (x: 1.0, y: 2.0));
    });
  });

  group('GraphLayoutStore', () {
    test('in-memory store saves and loads json', () async {
      final store = InMemoryGraphLayoutStore();
      expect(await store.load(), isNull);
      await store.save('{"nodes":[],"edges":[]}');
      expect(await store.load(), '{"nodes":[],"edges":[]}');
      await store.clear();
      expect(await store.load(), isNull);
    });
  });

  group('noteMatchesTypeFilter', () {
    const note = Note(path: 'notes/a.md', title: 'x', body: '', type: 'Idea');

    test('empty filter matches all', () {
      expect(noteMatchesTypeFilter(note, {}), isTrue);
    });

    test('selected types filter notes', () {
      expect(noteMatchesTypeFilter(note, {'Idea'}), isTrue);
      expect(noteMatchesTypeFilter(note, {'Task'}), isFalse);
      expect(noteMatchesTypeFilter(note, {'Idea', 'Task'}), isTrue);
    });
  });
}
