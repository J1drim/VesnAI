import 'package:shared_preferences/shared_preferences.dart';

abstract class GraphLayoutStore {
  Future<String?> load();
  Future<void> save(String json);
  Future<void> clear();
}

class SharedPreferencesGraphLayoutStore implements GraphLayoutStore {
  static const _key = 'vesnai.graphLayout';
  final SharedPreferences _prefs;

  SharedPreferencesGraphLayoutStore(this._prefs);

  @override
  Future<String?> load() async => _prefs.getString(_key);

  @override
  Future<void> save(String json) async {
    await _prefs.setString(_key, json);
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}

class InMemoryGraphLayoutStore implements GraphLayoutStore {
  String? _json;

  @override
  Future<String?> load() async => _json;

  @override
  Future<void> save(String json) async {
    _json = json;
  }

  @override
  Future<void> clear() async {
    _json = null;
  }
}
