import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okf_dart/okf_dart.dart';
import 'package:vesnai_app/desktop/sticky_board.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/models/note.dart';
import 'package:vesnai_app/providers.dart';
import 'package:vesnai_app/theme.dart';

void main() {
  testWidgets('sticky note card shows AI marker for generated notes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: VesnaiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: StickyNoteCard(
          note: Note(
            path: 'generated/x.md',
            title: 'Generated',
            body: 'made by vesna',
            origin: Origin.generated,
          ),
        ),
      ),
    ));
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(find.text('Generated'), findsOneWidget);
  });

  testWidgets('sticky board renders captured notes as cards', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(repositoryProvider)
        .capture(title: 'Desktop note', body: 'hi');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StickyBoard(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(StickyNoteCard), findsOneWidget);
    expect(find.text('Desktop note'), findsOneWidget);
  });
}
