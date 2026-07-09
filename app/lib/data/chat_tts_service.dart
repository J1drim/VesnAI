import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../features/chat/chat_sessions.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_outside_widgets.dart';
import '../providers.dart';
import 'api_client.dart';
import 'volume_gate.dart';
import 'voice_cache.dart';

/// Speaks assistant chat messages via server TTS + local cache.
class ChatTtsService {
  final Ref _ref;

  AppLocalizations get _l10n =>
      localizationsForAppLocale(_ref.read(appLocaleProvider));
  final AudioPlayer _player;
  final VolumeGate _volumeGate;
  int _speakGeneration = 0;

  /// Last file played (for tests).
  String? lastPlayedPath;

  ChatTtsService(this._ref, {AudioPlayer? player, VolumeGate? volumeGate})
      : _player = player ?? AudioPlayer(),
        _volumeGate = volumeGate ?? PlatformVolumeGate();

  Future<void> dispose() async {
    await _player.dispose();
  }

  int _nextGeneration() => ++_speakGeneration;

  bool _isCurrentGeneration(int gen) => gen == _speakGeneration;

  Future<bool> speak(
    ChatMessageView message, {
    bool auto = false,
    void Function(String message)? onError,
  }) async {
    if (message.id.isEmpty || message.content.trim().isEmpty) return false;

    if (!auto) {
      await stop();
    }
    final gen = _nextGeneration();

    if (auto) {
      final enabled = await _ref.read(readRepliesAloudProvider.future);
      if (!_isCurrentGeneration(gen)) return false;
      if (!enabled) return false;
      if (!await _volumeGate.canAutoSpeak()) return false;
      if (!_isCurrentGeneration(gen)) return false;
    }

    final client = _ref.read(apiClientProvider);
    final voiceCache = _ref.read(voiceCacheProvider);
    final hash = ttsContentHash(message.content);

    String? replayPath;
    if (message.hasTts &&
        ttsPathMatchesContent(message.ttsLocalPath, message.content) &&
        File(message.ttsLocalPath).existsSync()) {
      replayPath = message.ttsLocalPath;
    } else {
      replayPath = await voiceCache.existingPath(message.id, hash);
    }

    if (!_isCurrentGeneration(gen)) return false;

    if (replayPath != null &&
        replayPath.isNotEmpty &&
        File(replayPath).existsSync()) {
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        await _playFile(replayPath, gen);
      } else {
        lastPlayedPath = replayPath;
      }
      return _isCurrentGeneration(gen);
    }

    if (client == null) {
      onError?.call(_l10n.ttsNeedsServer);
      return false;
    }
    final settings = _ref.read(serverSettingsProvider).valueOrNull;
    final offline = (settings?['offline_only'] as bool?) ?? true;
    final voiceConfigured = settings?['voice_configured'] as bool?;
    if (!offline && voiceConfigured == false) {
      onError?.call(_l10n.ttsRegisterFirst);
      return false;
    }
    try {
      final chat = _ref.read(chatControllerProvider);
      final result = await client.tts(
        message.content,
        assistantLanguage: _ref.read(assistantLanguageProvider).apiValue,
        sessionId: chat.activeId,
      );
      if (!_isCurrentGeneration(gen)) return false;

      final ext = result.contentType.contains('mpeg') ? 'mp3' : 'wav';
      final savedPath = await voiceCache.write(message.id, hash, result.bytes, ext);
      if (!_isCurrentGeneration(gen)) return false;

      await _ref.read(chatControllerProvider.notifier).cacheTtsForMessage(
            message.id,
            savedPath,
          );
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        await _playFile(savedPath, gen);
      } else {
        lastPlayedPath = savedPath;
      }
      return _isCurrentGeneration(gen);
    } catch (e) {
      if (_isCurrentGeneration(gen)) {
        onError?.call(ttsErrorMessage(e, _l10n));
      }
      return false;
    }
  }

  Future<void> stop() async {
    _nextGeneration();
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> _playFile(String path, int gen) async {
    if (!_isCurrentGeneration(gen)) return;
    await _player.setFilePath(path);
    if (!_isCurrentGeneration(gen)) return;
    lastPlayedPath = path;
    await _player.play();
  }
}

final volumeGateProvider = Provider<VolumeGate>((ref) => PlatformVolumeGate());

final chatTtsServiceProvider = Provider<ChatTtsService>((ref) {
  final service = ChatTtsService(
    ref,
    volumeGate: ref.watch(volumeGateProvider),
  );
  ref.onDispose(() => service.dispose());
  return service;
});
