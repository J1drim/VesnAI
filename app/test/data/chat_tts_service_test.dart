import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vesnai_app/data/api_client.dart';
import 'package:vesnai_app/data/app_preferences.dart';
import 'package:vesnai_app/data/chat_tts_service.dart';
import 'package:vesnai_app/data/drift/database.dart';
import 'package:vesnai_app/data/voice_cache.dart';
import 'package:vesnai_app/features/chat/chat_sessions.dart';
import 'package:vesnai_app/providers.dart';

class _DelayedTtsClient extends http.BaseClient {
  final Map<String, Duration> delays;

  _DelayedTtsClient(this.delays);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/voice/tts')) {
      final body = await request.finalize().bytesToString();
      final message = jsonDecode(body)['message'] as String;
      await Future<void>.delayed(delays[message] ?? Duration.zero);
      return http.StreamedResponse(
        Stream.value(Uint8List.fromList([1, 2, 3])),
        200,
        headers: {'content-type': 'audio/wav'},
      );
    }
    return http.StreamedResponse(Stream.value([]), 404);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.ryanheise.just_audio.methods'),
    (call) async => null,
  );

  test('later speak wins when earlier TTS HTTP completes after cancel', () async {
    final voiceCache = VoiceCache(Directory.systemTemp.createTempSync('tts_race'));
    final httpClient = _DelayedTtsClient({
      'first reply': const Duration(milliseconds: 200),
      'second reply': Duration.zero,
    });
    final apiClient = VesnaiApiClient(
      baseUrl: Uri.parse('https://server.test'),
      token: 't',
      client: httpClient,
    );

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        voiceCacheProvider.overrideWith((ref) => voiceCache),
        vesnaiDatabaseProvider.overrideWith(
          (ref) => VesnaiDatabase(NativeDatabase.memory()),
        ),
        serverSettingsProvider.overrideWith(
          (ref) async => {'offline_only': false, 'voice_configured': true},
        ),
        chatControllerProvider.overrideWith(_EmptyChatController.new),
        appPreferencesStoreProvider.overrideWith((ref) => InMemoryAppPreferencesStore()),
      ],
    );
    addTearDown(container.dispose);

    final tts = container.read(chatTtsServiceProvider);
    const msgA = ChatMessageView(
      id: 'msg-a',
      role: 'assistant',
      content: 'first reply',
    );
    const msgB = ChatMessageView(
      id: 'msg-b',
      role: 'assistant',
      content: 'second reply',
    );

    unawaited(tts.speak(msgA, auto: false));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tts.speak(msgB, auto: false);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(tts.lastPlayedPath, isNotNull);
    expect(
      tts.lastPlayedPath,
      contains('_${ttsContentHash('second reply')}.'),
    );
    expect(
      tts.lastPlayedPath,
      isNot(contains('_${ttsContentHash('first reply')}.')),
    );
  });
}

class _EmptyChatController extends ChatController {
  @override
  ChatState build() => const ChatState(activeId: 'sess-1');
}
