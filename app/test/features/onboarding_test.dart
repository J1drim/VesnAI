import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/app.dart';
import 'package:vesnai_app/data/connection_store.dart';
import 'package:vesnai_app/data/server_discovery.dart';
import 'package:vesnai_app/providers.dart';

void main() {
  testWidgets('first run shows onboarding; skipping reveals the home shell',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        connectionStoreProvider.overrideWithValue(InMemoryConnectionStore()),
        serverDiscoveryProvider.overrideWithValue(const FakeServerDiscovery([])),
      ],
      child: const VesnaiApp(),
    ));
    // Discovery shows an ongoing-search spinner, so avoid pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Onboarding is shown when not paired and not onboarded. The action
    // buttons sit at the bottom of the scrollable page, so bring them into
    // view first (the default 800x600 test viewport cuts them off).
    await tester.ensureVisible(
      find.byKey(const Key('onboard-pair'), skipOffstage: false),
    );
    await tester.pump();
    expect(find.byKey(const Key('onboard-pair')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('onboard-skip'), skipOffstage: false),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboard-skip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // After continuing offline, the main app shell appears.
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
