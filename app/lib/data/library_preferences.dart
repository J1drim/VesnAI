import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local presentation preferences, separate from synced note metadata.
final libraryPreferencesStorageProvider = Provider<SharedPreferences?>(
  (ref) => null,
);
final libraryPreferencesProvider =
    StateNotifierProvider<LibraryPreferences, Map<String, dynamic>>(
      (ref) => LibraryPreferences(ref.watch(libraryPreferencesStorageProvider)),
    );

class LibraryPreferences extends StateNotifier<Map<String, dynamic>> {
  final SharedPreferences? storage;
  LibraryPreferences(this.storage) : super(_load(storage));

  static Map<String, dynamic> _load(SharedPreferences? storage) {
    try {
      return (jsonDecode(storage?.getString('library_preferences') ?? '{}')
              as Map)
          .cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> set(String key, dynamic value) async {
    state = {...state, key: value};
    await storage?.setString('library_preferences', jsonEncode(state));
  }
}
