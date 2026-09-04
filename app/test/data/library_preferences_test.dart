import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vesnai_app/data/library_preferences.dart';

void main() {
  test('theme and list preference survive a fresh controller', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final first = LibraryPreferences(storage);
    await first.set('theme', 'dark');
    await first.set('grid', false);
    final restored = LibraryPreferences(storage);
    expect(restored.state, {'theme': 'dark', 'grid': false});
    first.dispose();
    restored.dispose();
  });
}
