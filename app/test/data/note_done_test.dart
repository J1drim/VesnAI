import 'package:flutter_test/flutter_test.dart';
import 'package:okf_dart/okf_dart.dart';
import 'package:vesnai_app/models/note.dart';

void main() {
  test('Note.fromApi reads done and done_at', () {
    final note = Note.fromApi({
      'path': 'notes/shopping.md',
      'title': 'Shopping',
      'body': 'milk',
      'done': true,
      'done_at': '2026-07-07T09:00:00+00:00',
    });
    expect(note.done, isTrue);
    expect(note.doneAt, '2026-07-07T09:00:00+00:00');

    final open = Note.fromApi({'path': 'notes/open.md'});
    expect(open.done, isFalse);
    expect(open.doneAt, isEmpty);
  });

  test('done round-trips through the OKF concept (offline sync doc)', () {
    const note = Note(
      path: 'notes/shopping.md',
      title: 'Shopping',
      body: 'milk',
      done: true,
      doneAt: '2026-07-07T09:00:00+00:00',
    );
    final concept = note.toConcept();
    final back = Note.fromConcept(note.path, concept);
    expect(back.done, isTrue);
    expect(back.doneAt, '2026-07-07T09:00:00+00:00');

    // Reopened notes drop the done flag from the doc.
    final reopened =
        Note.fromConcept(note.path, note.copyWith(done: false).toConcept());
    expect(reopened.done, isFalse);
  });

  test('done survives the serialized sync push doc (dump + parse)', () {
    // Mirrors SyncEngine.flush(): pending note -> dumpConcept -> wire ->
    // parseConcept on the other side.
    const note = Note(
      path: 'notes/shopping.md',
      title: 'Shopping',
      body: 'milk',
      done: true,
      doneAt: '2026-07-08T08:00:00Z',
      syncState: SyncState.pendingUpdate,
    );
    final doc = dumpConcept(note.toConcept());
    final back = Note.fromConcept(note.path, parseConcept(doc));
    expect(back.done, isTrue);
    expect(back.doneAt, '2026-07-08T08:00:00Z');
  });

  test('copyWith toggles done both ways', () {
    const note = Note(path: 'notes/x.md');
    final marked = note.copyWith(done: true, doneAt: '2026-01-01T00:00:00Z');
    expect(marked.done, isTrue);
    final reopened = marked.copyWith(done: false, doneAt: '');
    expect(reopened.done, isFalse);
    expect(reopened.doneAt, isEmpty);
  });
}
