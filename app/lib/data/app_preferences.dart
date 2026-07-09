import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Fixed assistant reply/TTS language, or [AssistantLanguage.auto] to follow chat.
enum AssistantLanguage {
  auto,
  pl,
  en;

  static AssistantLanguage parse(String? raw) {
    switch (raw) {
      case 'pl':
        return AssistantLanguage.pl;
      case 'en':
        return AssistantLanguage.en;
      default:
        return AssistantLanguage.auto;
    }
  }

  /// Value sent to the server; ``null`` means auto-detect from the session.
  String? get apiValue => switch (this) {
        AssistantLanguage.auto => null,
        AssistantLanguage.pl => 'pl',
        AssistantLanguage.en => 'en',
      };

  String get label => switch (this) {
        AssistantLanguage.auto => 'Auto (from chat)',
        AssistantLanguage.pl => 'Polski',
        AssistantLanguage.en => 'English',
      };
}

/// UI locale of the app itself (not the assistant reply language).
enum AppLocale {
  system,
  en,
  pl;

  static AppLocale parse(String? raw) {
    switch (raw) {
      case 'en':
        return AppLocale.en;
      case 'pl':
        return AppLocale.pl;
      default:
        return AppLocale.system;
    }
  }

  /// Language code for `MaterialApp.locale`; null follows the device locale.
  String? get languageCode => switch (this) {
        AppLocale.system => null,
        AppLocale.en => 'en',
        AppLocale.pl => 'pl',
      };
}

abstract class AppPreferencesStore {
  Future<AppLocale> appLocale();
  Future<void> setAppLocale(AppLocale value);
  Future<AssistantLanguage> assistantLanguage();
  Future<void> setAssistantLanguage(AssistantLanguage value);
  Future<bool> readRepliesAloud();
  Future<void> setReadRepliesAloud(bool value);
  Future<bool> shareLocationWithChat();
  Future<void> setShareLocationWithChat(bool value);
  Future<String?> savedChatLocationJson();
  Future<void> setSavedChatLocationJson(String? value);
}

class SecureAppPreferencesStore implements AppPreferencesStore {
  static const _kAppLocale = 'vesnai.appLocale';
  static const _kAssistantLanguage = 'vesnai.assistantLanguage';
  static const _kReadRepliesAloud = 'vesnai.readRepliesAloud';
  static const _kShareLocationWithChat = 'vesnai.shareLocationWithChat';
  static const _kSavedChatLocation = 'vesnai.savedChatLocation';
  final FlutterSecureStorage _storage;

  SecureAppPreferencesStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<AppLocale> appLocale() async {
    final raw = await _storage.read(key: _kAppLocale);
    return AppLocale.parse(raw);
  }

  @override
  Future<void> setAppLocale(AppLocale value) async {
    await _storage.write(key: _kAppLocale, value: value.name);
  }

  @override
  Future<AssistantLanguage> assistantLanguage() async {
    final raw = await _storage.read(key: _kAssistantLanguage);
    return AssistantLanguage.parse(raw);
  }

  @override
  Future<void> setAssistantLanguage(AssistantLanguage value) async {
    await _storage.write(
      key: _kAssistantLanguage,
      value: value == AssistantLanguage.auto ? 'auto' : value.apiValue,
    );
  }

  @override
  Future<bool> readRepliesAloud() async {
    final raw = await _storage.read(key: _kReadRepliesAloud);
    if (raw == null) return true;
    return raw != 'false';
  }

  @override
  Future<void> setReadRepliesAloud(bool value) async {
    await _storage.write(key: _kReadRepliesAloud, value: value.toString());
  }

  @override
  Future<bool> shareLocationWithChat() async {
    final raw = await _storage.read(key: _kShareLocationWithChat);
    return raw == 'true';
  }

  @override
  Future<void> setShareLocationWithChat(bool value) async {
    await _storage.write(key: _kShareLocationWithChat, value: value.toString());
  }

  @override
  Future<String?> savedChatLocationJson() async {
    return _storage.read(key: _kSavedChatLocation);
  }

  @override
  Future<void> setSavedChatLocationJson(String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: _kSavedChatLocation);
    } else {
      await _storage.write(key: _kSavedChatLocation, value: value);
    }
  }
}

class InMemoryAppPreferencesStore implements AppPreferencesStore {
  AppLocale _appLocale = AppLocale.system;
  AssistantLanguage _language = AssistantLanguage.auto;
  bool _readRepliesAloud = true;
  bool _shareLocationWithChat = false;
  String? _savedChatLocationJson;

  @override
  Future<AppLocale> appLocale() async => _appLocale;

  @override
  Future<void> setAppLocale(AppLocale value) async {
    _appLocale = value;
  }

  @override
  Future<AssistantLanguage> assistantLanguage() async => _language;

  @override
  Future<void> setAssistantLanguage(AssistantLanguage value) async {
    _language = value;
  }

  @override
  Future<bool> readRepliesAloud() async => _readRepliesAloud;

  @override
  Future<void> setReadRepliesAloud(bool value) async {
    _readRepliesAloud = value;
  }

  @override
  Future<bool> shareLocationWithChat() async => _shareLocationWithChat;

  @override
  Future<void> setShareLocationWithChat(bool value) async {
    _shareLocationWithChat = value;
  }

  @override
  Future<String?> savedChatLocationJson() async => _savedChatLocationJson;

  @override
  Future<void> setSavedChatLocationJson(String? value) async {
    _savedChatLocationJson = value;
  }
}
