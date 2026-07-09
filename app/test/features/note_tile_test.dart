import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okf_dart/okf_dart.dart';
import 'package:vesnai_app/features/notes/note_tile.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/models/note.dart';
import 'package:vesnai_app/theme.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: VesnaiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('user note shows no AI badge', (tester) async {
    await tester.pumpWidget(_wrap(const NoteTile(
      note: Note(path: 'notes/a.md', title: 'My note', body: 'mine'),
    )));
    expect(find.text('AI'), findsNothing);
    expect(find.byIcon(Icons.edit_note), findsOneWidget);
  });

  testWidgets('generated note shows the AI badge', (tester) async {
    await tester.pumpWidget(_wrap(const NoteTile(
      note: Note(
        path: 'generated/a.md',
        title: 'Generated image',
        body: 'made by vesna',
        origin: Origin.generated,
      ),
    )));
    expect(find.text('AI'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(find.byIcon(Icons.edit_note), findsOneWidget);
  });

  testWidgets('idea note shows lightbulb icon', (tester) async {
    await tester.pumpWidget(_wrap(const NoteTile(
      note: Note(path: 'notes/a.md', title: 'Bright', body: 'spark', type: 'Idea'),
    )));
    expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
  });

  testWidgets('task note shows task icon', (tester) async {
    await tester.pumpWidget(_wrap(const NoteTile(
      note: Note(path: 'notes/a.md', title: 'Todo', body: 'do it', type: 'Task'),
    )));
    expect(find.byIcon(Icons.task_alt), findsOneWidget);
  });

  testWidgets('generated idea shows AI badge and type icon', (tester) async {
    await tester.pumpWidget(_wrap(const NoteTile(
      note: Note(
        path: 'generated/a.md',
        title: 'AI idea',
        body: 'insight',
        type: 'Idea',
        origin: Origin.generated,
      ),
    )));
    expect(find.text('AI'), findsOneWidget);
    expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
  });

  testWidgets('note with image markdown shows Photo attached preview', (tester) async {
    await tester.pumpWidget(_wrap(const NoteTile(
      note: Note(
        path: 'notes/a.md',
        title: 'Sunset',
        body: '![IMG.jpg](attachments/IMG.jpg)',
        attachments: ['attachments/IMG.jpg'],
      ),
    )));
    expect(find.text('Photo attached'), findsOneWidget);
    expect(find.textContaining('attachments/'), findsNothing);
  });

  testWidgets('pending note shows an upload indicator', (tester) async {
    await tester.pumpWidget(_wrap(const NoteTile(
      note: Note(path: 'notes/a.md', title: 'Pending', syncState: SyncState.pendingCreate),
    )));
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
  });
}
