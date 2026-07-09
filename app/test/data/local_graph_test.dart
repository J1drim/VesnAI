import 'package:flutter_test/flutter_test.dart';
import 'package:okf_dart/okf_dart.dart';
import 'package:vesnai_app/data/local_graph.dart';
import 'package:vesnai_app/models/note.dart';

void main() {
  test('buildLocalGraph includes linked notes as edges', () {
    final notes = [
      const Note(
        path: 'notes/a.md',
        title: 'Alpha',
        links: ['notes/b.md'],
      ),
      const Note(path: 'notes/b.md', title: 'Beta'),
    ];

    final graph = buildLocalGraph(notes);
    final nodes = (graph['nodes'] as List).cast<Map<String, dynamic>>();
    final edges = (graph['edges'] as List).cast<Map<String, String>>();

    expect(nodes.map((n) => n['id']), ['notes/a.md', 'notes/b.md']);
    expect(edges, [
      {'source': 'notes/a.md', 'target': 'notes/b.md'},
    ]);
  });

  test('buildLocalGraph filters by origin and tags', () {
    final notes = [
      const Note(
        path: 'notes/user.md',
        title: 'Mine',
        tags: ['work'],
        origin: Origin.user,
      ),
      const Note(
        path: 'notes/ai.md',
        title: 'Generated',
        tags: ['work'],
        origin: Origin.generated,
      ),
    ];

    final userOnly = buildLocalGraph(notes, origin: 'user');
    expect((userOnly['nodes'] as List).length, 1);
    expect(userOnly['nodes'][0]['id'], 'notes/user.md');

    final tagged = buildLocalGraph(notes, tags: {'work'});
    expect((tagged['nodes'] as List).length, 2);
  });
}
