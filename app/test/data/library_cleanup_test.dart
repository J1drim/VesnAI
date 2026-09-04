import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/library_cleanup.dart';
import 'package:vesnai_app/models/note.dart';

void main() {
  test('cleanup is read-only and distinguishes explicit and body links', () {
    const notes = [
      Note(
        path: 'notes/a.md',
        title: 'First',
        body: 'Repeated text with enough content for comparison.',
        tags: ['work'],
      ),
      Note(
        path: 'notes/b.md',
        title: 'Copy',
        body: 'Repeated text with enough content for comparison.',
        tags: ['Work'],
      ),
      Note(
        path: 'notes/c.md',
        title: 'Links',
        tags: ['work'],
        links: ['notes/missing.md'],
        body:
            '[Missing](other.md) [Existing](a.md) [External](https://example.com/doc.md)',
      ),
    ];
    final suggestions = inspectLibrary(notes);
    expect(
      suggestions.where((s) => s.kind == 'duplicate').single.note.path,
      'notes/b.md',
    );
    expect(
      suggestions.where((s) => s.kind == 'tag').single.replacement,
      'work',
    );
    final broken = suggestions.where((s) => s.kind == 'broken').toList();
    expect(broken, hasLength(2));
    expect(broken.where((s) => s.editable).single.value, 'notes/missing.md');
    expect(notes[1].archived, isFalse);
    expect(notes[1].tags, ['Work']);
    expect(notes[2].links, ['notes/missing.md']);
  });
}
