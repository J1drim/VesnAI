import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vesnai_app/data/speech_input.dart';
import 'package:vesnai_app/features/chat/chat_screen.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/providers.dart';

import '../helpers/chat_test_overrides.dart';

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
      Future.value(const SpeechResult('cześć', isFinal: false)),
      Future.value(const SpeechResult('cześć VesnAI', isFinal: true)),
    ]);
  }

  @override
  Future<void> stop() async => _listening = false;
}

http.Response _sessionJson({List<Map<String, dynamic>> messages = const []}) =>
    http.Response(
      jsonEncode({
        'id': 's1',
        'title': 'New chat',
        'created': '',
        'updated': '',
        'messages': messages,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

MockClient _chatMock({
  required void Function(String path) onPath,
  Map<String, http.Response Function(http.Request)>? handlers,
  List<Map<String, dynamic>> sessionMessages = const [],
}) {
  return MockClient((req) async {
    onPath(req.url.path);
    final handler = handlers?[req.url.path];
    if (handler != null) return handler(req);
    if (req.url.path == '/v1/chat/sessions' && req.method == 'GET') {
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'});
    }
    if (req.url.path == '/v1/chat/sessions' && req.method == 'POST') {
      return _sessionJson();
    }
    if (req.url.path.startsWith('/v1/chat/sessions/') && req.method == 'GET') {
      return _sessionJson(messages: sessionMessages);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  initFlutterTestBinding();

  testWidgets('mic transcribes on-device, shows user text, and enqueues chat',
      (tester) async {
    final paths = <String>[];
    final mock = _chatMock(
      onPath: paths.add,
      handlers: {
        '/v1/chat': (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['message'], 'cześć VesnAI');
          return http.Response(
            jsonEncode({
              'status': 'accepted',
              'session_id': 's1',
              'user_message_id': 'u1',
              'assistant_message_id': 'a1',
            }),
            202,
            headers: {'content-type': 'application/json'},
          );
        },
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...chatTestOverrides(httpClient: mock),
        speechInputProvider.overrideWith((ref) => _FakeSpeech()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChatScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('chat-mic')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));

    expect(paths, contains('/v1/chat'));
    expect(find.text('cześć VesnAI'), findsOneWidget);
  });

  testWidgets('Speak synthesizes the reply in the language of the user turn',
      (tester) async {
    String? ttsLanguage;
    final paths = <String>[];
    final mock = _chatMock(
      onPath: paths.add,
      sessionMessages: [
        {'role': 'user', 'content': 'Jaka jest pogoda?', 'id': 'u1', 'ts': ''},
        {'role': 'assistant', 'content': 'odpowiedź', 'id': 'a1', 'ts': ''},
      ],
      handlers: {
        '/v1/chat': (_) => http.Response(
              jsonEncode({
                'status': 'accepted',
                'session_id': 's1',
                'user_message_id': 'u1',
                'assistant_message_id': 'a1',
              }),
              202,
              headers: {'content-type': 'application/json'},
            ),
        '/v1/settings': (_) => http.Response(
              jsonEncode({'offline_only': false, 'voice_configured': true}),
              200,
              headers: {'content-type': 'application/json'},
            ),
        '/v1/voice/tts': (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          ttsLanguage = body['language'] as String?;
          return http.Response('RIFFfake', 200,
              headers: {'content-type': 'audio/wav'});
        },
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: chatTestOverrides(httpClient: mock),
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChatScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byKey(const Key('chat-input')), 'Jaka jest pogoda?');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('odpowiedź'), findsOneWidget);

    final speakButton = find.byWidgetPredicate(
      (w) => w is IconButton && w.key?.toString().contains('speak-') == true,
    );
    expect(speakButton, findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(speakButton);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(paths, contains('/v1/voice/tts'));
    expect(ttsLanguage, isNull);
  });

  testWidgets('Speak uses Polish voice when reply text is Polish even if UI locale is English',
      (tester) async {
    String? ttsLanguage;
    final mock = _chatMock(
      onPath: (_) {},
      sessionMessages: [
        {'role': 'user', 'content': 'hello', 'id': 'u1', 'ts': ''},
        {
          'role': 'assistant',
          'content': 'To jest odpowiedź po polsku bez ogonków w calym zdaniu.',
          'id': 'a1',
          'ts': '',
        },
      ],
      handlers: {
        '/v1/chat': (_) => http.Response(
              jsonEncode({
                'status': 'accepted',
                'session_id': 's1',
                'user_message_id': 'u1',
                'assistant_message_id': 'a1',
              }),
              202,
              headers: {'content-type': 'application/json'},
            ),
        '/v1/settings': (_) => http.Response(
              jsonEncode({'offline_only': false, 'voice_configured': true}),
              200,
              headers: {'content-type': 'application/json'},
            ),
        '/v1/voice/tts': (req) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          ttsLanguage = body['language'] as String?;
          return http.Response('RIFFfake', 200,
              headers: {'content-type': 'audio/wav'});
        },
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: chatTestOverrides(httpClient: mock),
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChatScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byKey(const Key('chat-input')), 'hello');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    final speakButton = find.byWidgetPredicate(
      (w) => w is IconButton && w.key?.toString().contains('speak-') == true,
    );

    await tester.runAsync(() async {
      await tester.tap(speakButton);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(ttsLanguage, isNull);
  });
}
