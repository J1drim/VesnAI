import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/features/notes/note_type_ui.dart';
import 'package:vesnai_app/features/notes/notes_type_filter.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/theme.dart';

void main() {
  testWidgets('type filter chips toggle multi-select', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: VesnaiTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: NotesTypeFilterBar()),
        ),
      ),
    );

    expect(find.text('Idea'), findsOneWidget);
    expect(find.text('Clear filters'), findsNothing);

    await tester.tap(find.text('Idea'));
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(tester.element(find.byType(NotesTypeFilterBar)))
          .read(notesTypeFilterProvider),
      {'Idea'},
    );
    expect(find.text('Clear filters'), findsOneWidget);

    await tester.tap(find.text('Task'));
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(tester.element(find.byType(NotesTypeFilterBar)))
          .read(notesTypeFilterProvider),
      {'Idea', 'Task'},
    );

    // The bar scrolls horizontally; the clear button can sit past the edge.
    await tester.ensureVisible(find.text('Clear filters', skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(tester.element(find.byType(NotesTypeFilterBar)))
          .read(notesTypeFilterProvider),
      isEmpty,
    );
  });

  testWidgets('All chip enables and exits all-notes mode', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: VesnaiTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: NotesTypeFilterBar()),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotesTypeFilterBar)),
    );

    // Tap All: no type restriction and done notes shown.
    await tester.tap(find.byKey(const Key('show-all-filter')));
    await tester.pumpAndSettle();
    expect(container.read(notesTypeFilterProvider), isEmpty);
    expect(container.read(showDoneNotesProvider), isTrue);
    expect(
      notesFilterShowsAll(
        container.read(notesTypeFilterProvider),
        container.read(showDoneNotesProvider),
      ),
      isTrue,
    );

    // Tap a type chip: exits All mode and filters to that type.
    await tester.tap(find.text('Idea'));
    await tester.pumpAndSettle();
    expect(container.read(notesTypeFilterProvider), {'Idea'});
    expect(container.read(showDoneNotesProvider), isFalse);

    // Re-enable All, then tap All again to return to the default view.
    await tester.tap(find.byKey(const Key('show-all-filter')));
    await tester.pumpAndSettle();
    expect(container.read(notesTypeFilterProvider), isEmpty);
    expect(container.read(showDoneNotesProvider), isTrue);

    await tester.tap(find.byKey(const Key('show-all-filter')));
    await tester.pumpAndSettle();
    expect(container.read(notesTypeFilterProvider), isEmpty);
    expect(container.read(showDoneNotesProvider), isFalse);
  });
}
