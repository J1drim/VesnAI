import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/features/notes/projects_screen.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/models/note.dart';
import 'package:vesnai_app/providers.dart';

void main() {
  testWidgets('project overview enforces saved filters offline', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(localStoreProvider);
    for (final note in [
      const Note(
        path: 'notes/task.md',
        title: 'Project task',
        type: 'Task',
        tags: ['launch'],
      ),
      const Note(
        path: 'notes/private.md',
        title: 'Other project',
        tags: ['other'],
      ),
      const Note(
        path: 'notes/done.md',
        title: 'Already done',
        tags: ['launch'],
        done: true,
      ),
    ]) {
      await store.put(note);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProjectScreen(
            view: {'name': 'Launch', 'tag': 'launch', 'done': false},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Project task'), findsOneWidget);
    expect(find.text('Other project'), findsNothing);
    expect(find.text('Already done'), findsNothing);
    expect(
      find.text('1 notes · 1 open tasks · 0 research notes'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'What next?');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Ask about this project'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Project answers require'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
