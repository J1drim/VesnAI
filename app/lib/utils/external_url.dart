import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// True for links that should open in the system browser (vs. in-app
/// resources like `attachments/...` or `chat:` references).
bool isExternalUrl(String href) {
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https' || scheme == 'mailto';
}

/// Opens [href] in the system browser. Shows a SnackBar on failure when a
/// [context] is provided.
Future<void> openExternalUrl(String href, {BuildContext? context}) async {
  final uri = Uri.tryParse(href.trim());
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).couldNotOpenLink(href))),
    );
  }
}
