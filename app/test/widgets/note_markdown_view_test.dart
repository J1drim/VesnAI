import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/widgets/note_markdown_view.dart';

void main() {
  testWidgets(
    'Markdown renderer preserves tasks and private attachment builder',
    (tester) async {
      String? updated;
      Uri? image;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteMarkdownView(
              markdown:
                  '# Reading\n\n- [ ] Follow up\n\n'
                  '> Quoted **source**\n\n![Photo](attachments/private.png)',
              onTaskToggle: (body) async => updated = body,
              imageBuilder: (uri, title, alt) {
                image = uri;
                return Text('Local image: $alt');
              },
            ),
          ),
        ),
      );
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Local image: Photo'), findsOneWidget);
      expect(image.toString(), 'attachments/private.png');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(updated, contains('- [x] Follow up'));
      expect(updated, contains('![Photo](attachments/private.png)'));
      expect(tester.takeException(), isNull);
    },
  );
}
