import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted, paired-server credentials (token + base URL + device id).
typedef SavedConnection = ({String baseUrl, String token, String? deviceId});

/// Durable store for the paired-server connection and onboarding state.
///
/// Behind an interface so the secure (Keychain/Keystore) implementation can be
/// swapped for an in-memory fake in tests with no platform channels.
abstract class ConnectionStore {
  Future<SavedConnection?> load();
  Future<void> save({required String baseUrl, required String token, String? deviceId});
  Future<void> clear();
  Future<bool> isOnboarded();
  Future<void> setOnboarded();
}

class SecureConnectionStore implements ConnectionStore {
  static const _kBaseUrl = 'vesnai.baseUrl';
  static const _kToken = 'vesnai.token';
  static const _kDeviceId = 'vesnai.deviceId';
  static const _kOnboarded = 'vesnai.onboarded';

  final FlutterSecureStorage _storage;

  SecureConnectionStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<SavedConnection?> load() async {
    final baseUrl = await _storage.read(key: _kBaseUrl);
    final token = await _storage.read(key: _kToken);
    if (baseUrl == null || token == null) return null;
    return (baseUrl: baseUrl, token: token, deviceId: await _storage.read(key: _kDeviceId));
  }

  @override
  Future<void> save(
      {required String baseUrl, required String token, String? deviceId}) async {
    await _storage.write(key: _kBaseUrl, value: baseUrl);
    await _storage.write(key: _kToken, value: token);
    if (deviceId != null) await _storage.write(key: _kDeviceId, value: deviceId);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _kBaseUrl);
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kDeviceId);
  }

  @override
  Future<bool> isOnboarded() async =>
      (await _storage.read(key: _kOnboarded)) == 'true';

  @override
  Future<void> setOnboarded() async =>
      _storage.write(key: _kOnboarded, value: 'true');
}

/// In-memory store for tests.
class InMemoryConnectionStore implements ConnectionStore {
  SavedConnection? _conn;
  bool _onboarded = false;

  @override
  Future<SavedConnection?> load() async => _conn;

  @override
  Future<void> save(
          {required String baseUrl, required String token, String? deviceId}) async =>
      _conn = (baseUrl: baseUrl, token: token, deviceId: deviceId);

  @override
  Future<void> clear() async => _conn = null;

  @override
  Future<bool> isOnboarded() async => _onboarded;

  @override
  Future<void> setOnboarded() async => _onboarded = true;
}
