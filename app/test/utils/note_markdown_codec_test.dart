import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/utils/note_markdown_codec.dart';

void main() {
  final codec = NoteMarkdownCodec();

  test('round-trips bold text', () {
    const input = 'Hello **world**';
    final doc = codec.markdownToDocument(input);
    final output = codec.documentToMarkdown(doc);
    expect(output, contains('**world**'));
  });

  test('round-trips header', () {
    const input = '# Title\n\nBody';
    final doc = codec.markdownToDocument(input);
    final output = codec.documentToMarkdown(doc);
    expect(output, contains('# Title'));
  });

  test('round-trips bullet list', () {
    const input = '- one\n- two';
    final doc = codec.markdownToDocument(input);
    final output = codec.documentToMarkdown(doc);
    expect(output, contains('- one'));
    expect(output, contains('- two'));
  });

  test('round-trips checklist', () {
    const input = '- [ ] todo\n- [x] done';
    final doc = codec.markdownToDocument(input);
    final output = codec.documentToMarkdown(doc);
    expect(output, contains('- [ ]'));
    expect(output, contains('- [x]'));
  });

  test('preserves attachment image markdown', () {
    const input = 'See photo\n\n![](attachments/abc.png)';
    final doc = codec.markdownToDocument(input);
    final output = codec.documentToMarkdown(doc);
    expect(output, contains('attachments/abc.png'));
  });

  test('empty body yields empty markdown', () {
    final doc = codec.markdownToDocument('');
    expect(codec.documentToMarkdown(doc), '');
  });
}
