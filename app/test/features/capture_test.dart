import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vesnai_app/data/attachment_cache.dart';
import 'package:vesnai_app/data/chat_attachment_cache.dart';
import 'package:vesnai_app/features/capture/capture_screen.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/providers.dart';

/// The body editor watches the attachment caches, which on device are opened
/// in main(); tests back them with a temp directory.
List<Override> _cacheOverrides() {
  final tmp = Directory.systemTemp.createTempSync('vesnai_capture_test');
  addTearDown(() => tmp.deleteSync(recursive: true));
  return [
    attachmentCacheProvider.overrideWith(
      (ref) => AttachmentCache(Directory(p.join(tmp.path, 'attachments'))),
    ),
    chatAttachmentCacheProvider.overrideWith(
      (ref) => ChatAttachmentCache(Directory(p.join(tmp.path, 'chat'))),
    ),
  ];
}

Widget _captureTestApp(Widget child) => ProviderScope(
      overrides: _cacheOverrides(),
      child: MaterialApp(
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

Future<void> _enterTitleText(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('title-field')), text);
  await tester.pump();
}

Future<void> _enterBodyText(WidgetTester tester, String text) async {
  await tester.tap(find.byKey(const Key('body-field')));
  await tester.pumpAndSettle();
  final editable = find.descendant(
    of: find.byKey(const Key('body-field')),
    matching: find.byType(EditableText),
  );
  if (editable.evaluate().isEmpty) return;
  await tester.enterText(editable, text);
  await tester.pump();
}

void main() {
  testWidgets('tag suggestions update as the user types', (tester) async {
    await tester.pumpWidget(_captureTestApp(const CaptureScreen()));

    expect(find.byKey(const Key('tag-misc')), findsOneWidget);

    await _enterTitleText(tester, 'a brilliant idea');
    expect(find.byKey(const Key('tag-idea')), findsOneWidget);
  });

  testWidgets('manual tag edits are not overwritten by heuristic', (tester) async {
    await tester.pumpWidget(_captureTestApp(const CaptureScreen()));

    await _enterTitleText(tester, 'a brilliant idea');
    expect(find.byKey(const Key('tag-idea')), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byKey(const Key('tag-idea')),
      matching: find.byType(Icon),
    ));
    await tester.pump();
    expect(find.byKey(const Key('tag-idea')), findsNothing);

    await _enterTitleText(tester, 'a brilliant idea more');
    expect(find.byKey(const Key('tag-idea')), findsNothing);
  });

  testWidgets('user can add a custom tag via the tag sheet', (tester) async {
    await tester.pumpWidget(_captureTestApp(const CaptureScreen()));

    await tester.tap(find.byKey(const Key('add-tag-chip')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-sheet-field')), 'weekend');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tag-weekend')), findsOneWidget);
  });

  testWidgets('type sheet changes the note type chip', (tester) async {
    await tester.pumpWidget(_captureTestApp(const CaptureScreen()));

    await tester.tap(find.byKey(const Key('meta-type-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('type-option-Task')));
    await tester.pumpAndSettle();

    final chip = find.byKey(const Key('meta-type-chip'));
    expect(
      find.descendant(of: chip, matching: find.text('Task')),
      findsOneWidget,
    );
  });

  testWidgets('Aa toggle shows and hides the formatting toolbar',
      (tester) async {
    await tester.pumpWidget(_captureTestApp(const CaptureScreen()));

    expect(find.byType(QuillSimpleToolbar), findsNothing);

    await tester.tap(find.byKey(const Key('format-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(QuillSimpleToolbar), findsOneWidget);

    await tester.tap(find.byKey(const Key('format-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(QuillSimpleToolbar), findsNothing);
  });

  testWidgets('saving a note adds it to the notes list', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(ProviderScope(
      overrides: _cacheOverrides(),
      child: MaterialApp(
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const CaptureScreen();
        }),
      ),
    ));

    await _enterTitleText(tester, 'Buy milk');
    await _enterBodyText(tester, 'remember to buy milk');
    await tester.tap(find.byKey(const Key('save-note')));
    await tester.pumpAndSettle();

    final notes = await container.read(repositoryProvider).notes();
    expect(notes.length, 1);
    expect(notes.first.title, 'Buy milk');
  });
}
