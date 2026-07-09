import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vesnai_app/app.dart';
import 'package:vesnai_app/features/notes/note_tile.dart';

/// End-to-end: capture a note and see it appear in the list (offline-first,
/// in-memory store). Runs on a device/simulator in the nightly/e2e suite.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture -> appears in notes list', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: VesnaiApp()));
    await tester.pumpAndSettle();

    // First-run onboarding: continue without pairing.
    final skip = find.byKey(const Key('onboard-skip'));
    if (skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await tester.pumpAndSettle();
    }

    // Open capture.
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('title-field')), 'My first thought');
    await tester.enterText(find.byKey(const Key('body-field')), 'a brilliant idea');
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-note')));
    await tester.pumpAndSettle();

    expect(find.byType(NoteTile), findsOneWidget);
    expect(find.text('My first thought'), findsOneWidget);
  });
}
