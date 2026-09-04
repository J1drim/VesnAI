import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/features/notes/cleanup_screen.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/models/note.dart';
import 'package:vesnai_app/providers.dart';

void main() {
  testWidgets(
    'cleanup scans only on request and applies only after confirmation',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(localStoreProvider);
      await store.put(
        const Note(
          path: 'notes/a.md',
          title: 'Broken reference',
          links: ['notes/missing.md'],
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CleanupScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Broken reference'), findsNothing);
      await tester.tap(find.text('Scan library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Broken reference'));
      await tester.pumpAndSettle();
      expect((await store.get('notes/a.md'))!.links, ['notes/missing.md']);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Remove explicit link'),
      );
      await tester.pumpAndSettle();
      expect((await store.get('notes/a.md'))!.links, isEmpty);
      expect((await store.get('notes/a.md'))!.isPending, isTrue);
      expect(find.text('No suggestions from this check.'), findsOneWidget);
    },
  );
}
