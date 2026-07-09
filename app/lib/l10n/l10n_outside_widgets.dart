import 'dart:ui';

import '../data/app_preferences.dart';
import 'app_localizations.dart';

/// Resolve [AppLocalizations] outside a widget tree (services, notifiers,
/// background isolates). Falls back to English for unsupported locales.
AppLocalizations localizationsForLocale(Locale? locale) {
  final l = locale ?? PlatformDispatcher.instance.locale;
  return AppLocalizations.delegate.isSupported(l)
      ? lookupAppLocalizations(l)
      : lookupAppLocalizations(const Locale('en'));
}

/// Same, from the persisted app-language preference ([AppLocale]); `system`
/// follows the device locale.
AppLocalizations localizationsForAppLocale(AppLocale appLocale) {
  final code = appLocale.languageCode;
  return localizationsForLocale(code == null ? null : Locale(code));
}

/// For background isolates (no Riverpod container): read the stored
/// preference directly.
Future<AppLocalizations> localizationsFromPreferences(
    {AppPreferencesStore? store}) async {
  final prefs = store ?? SecureAppPreferencesStore();
  try {
    return localizationsForAppLocale(await prefs.appLocale());
  } catch (_) {
    return localizationsForLocale(null);
  }
}
