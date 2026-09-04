import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vesnai_app/app.dart';
import 'package:vesnai_app/data/attachment_cache.dart';
import 'package:vesnai_app/data/chat_attachment_cache.dart';
import 'package:vesnai_app/features/notes/note_tile.dart';
import 'package:vesnai_app/providers.dart';
import 'package:vesnai_app/widgets/note_body_editor.dart';

/// End-to-end: capture a note and see it appear in the list (offline-first,
/// in-memory store). Runs on a device/simulator in the nightly/e2e suite.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture -> appears in notes list', (tester) async {
    final directory = await Directory.systemTemp.createTemp('vesnai-e2e-');
    addTearDown(() => directory.delete(recursive: true));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardedProvider.overrideWith((ref) => true),
          attachmentCacheProvider.overrideWith(
            (ref) => AttachmentCache(Directory('${directory.path}/notes')),
          ),
          chatAttachmentCacheProvider.overrideWith(
            (ref) => ChatAttachmentCache(Directory('${directory.path}/chat')),
          ),
        ],
        child: const VesnaiApp(),
      ),
    );
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

    await tester.enterText(
      find.byKey(const Key('title-field')),
      'My first thought',
    );
    final editor = tester.widget<NoteBodyEditor>(
      find.byKey(const Key('body-field')),
    );
    editor.controller!.setMarkdown('a brilliant idea');
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-note')));
    await tester.pumpAndSettle();

    expect(find.byType(NoteTile), findsOneWidget);
    expect(find.text('My first thought'), findsOneWidget);
  });
}
