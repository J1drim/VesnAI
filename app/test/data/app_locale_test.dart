import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/app_preferences.dart';
import 'package:vesnai_app/providers.dart';

void main() {
  test('AppLocale parse and languageCode', () {
    expect(AppLocale.parse('pl'), AppLocale.pl);
    expect(AppLocale.parse('en'), AppLocale.en);
    expect(AppLocale.parse(null), AppLocale.system);
    expect(AppLocale.parse('garbage'), AppLocale.system);

    expect(AppLocale.system.languageCode, isNull);
    expect(AppLocale.pl.languageCode, 'pl');
    expect(AppLocale.en.languageCode, 'en');
  });

  test('AppLocaleController persists and hydrates the selection', () async {
    final store = InMemoryAppPreferencesStore();
    final container = ProviderContainer(
      overrides: [appPreferencesStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    expect(container.read(appLocaleProvider), AppLocale.system);

    await container.read(appLocaleProvider.notifier).set(AppLocale.pl);
    expect(container.read(appLocaleProvider), AppLocale.pl);
    expect(await store.appLocale(), AppLocale.pl);

    // A fresh container (new app start) restores the stored locale on hydrate.
    final restarted = ProviderContainer(
      overrides: [appPreferencesStoreProvider.overrideWithValue(store)],
    );
    addTearDown(restarted.dispose);
    expect(restarted.read(appLocaleProvider), AppLocale.system);
    await restarted.read(appLocaleProvider.notifier).hydrate();
    expect(restarted.read(appLocaleProvider), AppLocale.pl);
  });
}
