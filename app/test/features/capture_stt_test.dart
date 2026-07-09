import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vesnai_app/data/attachment_cache.dart';
import 'package:vesnai_app/data/chat_attachment_cache.dart';
import 'package:vesnai_app/data/speech_input.dart';
import 'package:vesnai_app/features/capture/capture_screen.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/providers.dart';
import 'package:vesnai_app/widgets/note_body_editor.dart';

class _FakeSpeech implements SpeechInputService {
  bool _listening = false;
  @override
  bool get isListening => _listening;
  @override
  Future<bool> initialize() async => true;
  @override
  Stream<SpeechResult> listen({
    String? localeId,
    Duration pauseFor = const Duration(seconds: 3),
    Duration listenFor = const Duration(minutes: 2),
  }) {
    _listening = true;
    return Stream.fromFutures([
      Future.value(const SpeechResult('kup', isFinal: false)),
      Future.value(const SpeechResult('kup mleko', isFinal: true)),
    ]);
  }

  @override
  Future<void> stop() async => _listening = false;
}

List<Override> _overrides() {
  final tmp = Directory.systemTemp.createTempSync('vesnai_capture_stt_test');
  addTearDown(() => tmp.deleteSync(recursive: true));
  return [
    attachmentCacheProvider.overrideWith(
      (ref) => AttachmentCache(Directory(p.join(tmp.path, 'attachments'))),
    ),
    chatAttachmentCacheProvider.overrideWith(
      (ref) => ChatAttachmentCache(Directory(p.join(tmp.path, 'chat'))),
    ),
    speechInputProvider.overrideWith((ref) => _FakeSpeech()),
  ];
}

Widget _app() => ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CaptureScreen(),
      ),
    );

Future<void> _dictate(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('capture-mic')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('dictation goes to the title when it has focus', (tester) async {
    await tester.pumpWidget(_app());

    await tester.tap(find.byKey(const Key('title-field')));
    await tester.pump();

    await _dictate(tester);

    final title =
        tester.widget<TextField>(find.byKey(const Key('title-field')));
    expect(title.controller!.text, 'kup mleko');
  });

  testWidgets('dictation goes to the body when it has focus', (tester) async {
    await tester.pumpWidget(_app());

    await tester.tap(find.byKey(const Key('body-field')));
    await tester.pumpAndSettle();

    await _dictate(tester);

    final editor =
        tester.widget<NoteBodyEditor>(find.byKey(const Key('body-field')));
    expect(editor.controller!.markdown.trim(), 'kup mleko');

    final title =
        tester.widget<TextField>(find.byKey(const Key('title-field')));
    expect(title.controller!.text, isEmpty);
  });
}
