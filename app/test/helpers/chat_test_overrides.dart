import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vesnai_app/data/app_preferences.dart';
import 'package:vesnai_app/data/attachment_cache.dart';
import 'package:vesnai_app/data/chat_attachment_cache.dart';
import 'package:vesnai_app/data/chat_store.dart';
import 'package:vesnai_app/data/drift/database.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/data/shared_storage.dart';
import 'package:vesnai_app/data/chat_tts_service.dart';
import 'package:vesnai_app/data/voice_cache.dart';
import 'package:vesnai_app/data/volume_gate.dart';
import 'package:vesnai_app/features/chat/chat_sessions.dart';
import 'package:vesnai_app/providers.dart';

class PairedConnectionController extends ConnectionController {
  @override
  ServerConnection build() => ServerConnection(
        baseUrl: Uri.parse('https://server.test'),
        token: 't',
        deviceId: 'd',
      );
}

VoiceCache _testVoiceCache() =>
    VoiceCache(Directory.systemTemp.createTempSync('voice_cache_test'));

AttachmentCache _testAttachmentCache() =>
    AttachmentCache(Directory.systemTemp.createTempSync('attachment_cache_test'));

ChatAttachmentCache _testChatAttachmentCache() =>
    ChatAttachmentCache(Directory.systemTemp.createTempSync('chat_attachment_cache_test'));

/// Shared Riverpod overrides for chat-related tests (in-memory Drift, no platform channels).
List<Override> chatTestOverrides({required http.Client httpClient}) {
  final db = VesnaiDatabase(NativeDatabase.memory());
  return [
      httpClientProvider.overrideWith((ref) => httpClient),
      serverConnectionProvider.overrideWith(PairedConnectionController.new),
      serverSettingsProvider.overrideWith(
        (ref) async => {'offline_only': false, 'voice_configured': true},
      ),
      voiceCacheProvider.overrideWith((ref) => _testVoiceCache()),
      attachmentCacheProvider.overrideWith((ref) => _testAttachmentCache()),
      chatAttachmentCacheProvider.overrideWith((ref) => _testChatAttachmentCache()),
      vesnaiDatabaseProvider.overrideWith((ref) => db),
      volumeGateProvider.overrideWith((ref) => NeverSpeakVolumeGate()),
      sharedWidgetStorageProvider.overrideWith((ref) => InMemorySharedWidgetStorage()),
      appPreferencesStoreProvider.overrideWith((ref) => InMemoryAppPreferencesStore()),
    ];
}

void initFlutterTestBinding() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.ryanheise.just_audio.methods'),
    (call) async => null,
  );
}
