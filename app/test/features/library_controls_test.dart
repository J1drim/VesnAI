import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/library_preferences.dart';
import 'package:vesnai_app/features/notes/library_controls.dart';
import 'package:vesnai_app/features/notes/note_connections.dart';
import 'package:vesnai_app/features/notes/note_type_ui.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/models/note.dart';
import 'package:vesnai_app/providers.dart';

Widget app(ProviderContainer container, Widget child) => UncontrolledProviderScope(container: container,
  child: MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: child)));

void main() {
  testWidgets('saved views restore query, tag, type, completion and order', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final prefs = container.read(libraryPreferencesProvider.notifier);
    await prefs.set('tag', 'project');
    await prefs.set('sort', 'title');
    container.read(notesTypeFilterProvider.notifier).state = {'Idea'};
    container.read(showDoneNotesProvider.notifier).state = true;
    var query = '';
    await tester.pumpWidget(app(container, LibraryControls(query: 'creative', onQuery: (value) => query = value)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bookmarks_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save this view'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Creative project');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((container.read(libraryPreferencesProvider)['views'] as List).single['query'], 'creative');
    await prefs.set('tag', 'other');
    container.read(notesTypeFilterProvider.notifier).state = {};
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bookmarks_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Creative project'));
    await tester.pumpAndSettle();
    expect(query, 'creative');
    expect(container.read(libraryPreferencesProvider)['tag'], 'project');
    expect(container.read(notesTypeFilterProvider), {'Idea'});
    expect(container.read(showDoneNotesProvider), true);
  });

  testWidgets('offline backlinks and outgoing links are displayed without AI', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const current = Note(path: 'notes/a.md', title: 'Current', links: ['notes/b.md']);
    for (final note in [current, const Note(path: 'notes/b.md', title: 'Outgoing'),
      const Note(path: 'notes/c.md', title: 'Incoming', body: '[Current](a.md)')]) {
      await container.read(localStoreProvider).put(note);
    }
    await tester.pumpWidget(app(container, NoteConnections(note: current)));
    await tester.pumpAndSettle();
    expect(find.text('Incoming'), findsOneWidget);
    expect(find.text('Outgoing'), findsOneWidget);
    expect(find.text('Find related notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
