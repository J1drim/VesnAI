import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/attachment_cache.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/features/notes/recovery_screen.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/models/note.dart';
import 'package:vesnai_app/providers.dart';

void main() {
  testWidgets('offline deletion safety copy restores as a new pending note', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('vesnai-recovery-widget');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = InMemoryNoteStore();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        attachmentCacheProvider.overrideWithValue(AttachmentCache(dir)),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(syncEngineProvider)
        .saveLocal(
          const Note(
            path: 'notes/original.md',
            title: 'Safety copy',
            body: 'Unsent text',
          ),
        );
    await container.read(syncEngineProvider).deleteLocal('notes/original.md');
    expect(await store.all(), isEmpty);
    expect(jsonDecode((await store.localValue('local_trash'))!), hasLength(1));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const RecoveryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Safety copy'), findsOneWidget);
    await tester.tap(find.text('Safety copy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Restore note'));
    await tester.pumpAndSettle();
    final note = (await store.all()).single;
    expect(note.body, 'Unsent text');
    expect(note.path, isNot('notes/original.md'));
    expect(note.syncState, SyncState.pendingCreate);
    expect(jsonDecode((await store.localValue('local_trash'))!), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
