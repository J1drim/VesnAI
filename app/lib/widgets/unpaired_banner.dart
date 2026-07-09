import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/settings_screen.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

/// Call-to-action shown at the top of the notes list and chat when the device
/// is not paired: explains what pairing unlocks and opens the pair dialog.
class UnpairedBanner extends ConsumerWidget {
  const UnpairedBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paired = ref.watch(serverConnectionProvider).isPaired;
    if (paired) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.link_off, size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.unpairedBannerText,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSecondaryContainer),
              ),
            ),
            TextButton(
              key: const Key('unpaired-banner-pair'),
              onPressed: () => showPairServerDialog(context, ref),
              child: Text(l.pair),
            ),
          ],
        ),
      ),
    );
  }
}
