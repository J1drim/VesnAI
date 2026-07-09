import 'package:flutter_test/flutter_test.dart';
import 'package:okf_dart/okf_dart.dart';
import 'package:vesnai_app/features/notes/note_preview.dart';
import 'package:vesnai_app/models/note.dart';

void main() {
  test('notePreviewBody strips markdown images', () {
    const note = Note(
      path: 'notes/a.md',
      title: 'Pic',
      body: 'Hello\n\n![photo.jpg](attachments/photo.jpg)',
    );
    expect(notePreviewBody(note), 'Hello');
  });

  test('notePreviewBody shows Photo attached when only images', () {
    const note = Note(
      path: 'notes/a.md',
      body: '![photo.jpg](attachments/photo.jpg)',
      attachments: ['attachments/photo.jpg'],
    );
    expect(notePreviewBody(note), 'Photo attached');
  });

  test('noteVisibleInMainList hides enrichment children and chat transcripts', () {
    const transcript = Note(
      path: 'memory/chats/s1.md',
      type: 'ChatTranscript',
      origin: Origin.generated,
    );
    const enrichImage = Note(
      path: 'notes/gen.md',
      type: 'GeneratedImage',
      origin: Origin.generated,
      source: 'notes/parent.md',
    );
    const enrichCaption = Note(
      path: 'notes/cap.md',
      type: 'GeneratedCaption',
      origin: Origin.generated,
      source: 'notes/photo.md',
    );
    const chatSaved = Note(
      path: 'notes/chat-img.md',
      type: 'Photo',
      tags: ['chat'],
      origin: Origin.user,
    );
    const shown = Note(path: 'notes/parent.md', title: 'Parent');
    expect(noteVisibleInMainList(transcript), isFalse);
    expect(noteVisibleInMainList(enrichImage), isFalse);
    expect(noteVisibleInMainList(enrichCaption), isFalse);
    expect(noteVisibleInMainList(chatSaved), isTrue);
    expect(noteVisibleInMainList(shown), isTrue);
  });

  test('noteVisibleInMainList hides sync conflict copies', () {
    const conflict = Note(path: 'notes/a.conflict-phone.md', title: 'Conflict');
    expect(noteVisibleInMainList(conflict), isFalse);
  });

  test('toConcept preserves vesnai version', () {
    const note = Note(path: 'notes/a.md', version: 3);
    expect(note.toConcept().vesnai['version'], 3);
  });

  test('toConcept always includes attachments key', () {
    const note = Note(path: 'notes/a.md', attachments: ['attachments/x.png']);
    final vesnai = note.toConcept().vesnai;
    expect(vesnai['attachments'], ['attachments/x.png']);
  });

  test('fromApi preserves version and updated', () {
    final note = Note.fromApi({
      'path': 'notes/a.md',
      'title': 'A',
      'body': 'b',
      'type': 'Note',
      'origin': 'user',
      'tags': [],
      'links': [],
      'attachments': [],
      'version': 4,
      'updated': '2026-06-30T12:00:00Z',
    });
    expect(note.version, 4);
    expect(note.updated, '2026-06-30T12:00:00Z');
  });
}
