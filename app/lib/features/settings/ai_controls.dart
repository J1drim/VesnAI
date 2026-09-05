import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';

class AiControls extends ConsumerStatefulWidget {
  const AiControls({super.key});
  @override
  ConsumerState<AiControls> createState() => _AiControlsState();
}

class _AiControlsState extends ConsumerState<AiControls> {
  Map? _checked;
  bool _busy = false;
  String? _server;
  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(apiClientProvider)!
          .libraryRecovery('services/check', method: 'POST');
      if (mounted) setState(() => _checked = result['services'] as Map);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).servicesUnavailable),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final server = ref.watch(serverConnectionProvider).baseUrl?.toString();
    if (_server != server) {
      _server = server;
      _checked = null;
    }
    final settings = ref.watch(serverSettingsProvider).valueOrNull;
    final statuses = _checked ?? settings?['service_status'] as Map? ?? {};
    return ExpansionTile(
      title: Text(l.aiBehavior),
      leading: const Icon(Icons.tune),
      children: [
        SwitchListTile(
          value: settings?['auto_illustrate'] == true,
          onChanged: null,
          title: Text(l.automaticImages),
          subtitle: Text(
            settings?.containsKey('auto_illustrate') == true
                ? l.serverManagedBehavior
                : l.servicesUnavailable,
          ),
        ),
        SwitchListTile(
          value: settings?['marena_enabled'] == true,
          onChanged: null,
          title: Text(l.automaticCritiques),
          subtitle: Text(
            settings?.containsKey('marena_enabled') == true
                ? l.serverManagedBehavior
                : l.servicesUnavailable,
          ),
        ),
        for (final service in [
          'chat',
          'embeddings',
          'images',
          'vision',
          'voice',
          'critique',
        ])
          ListTile(
            title: Text(switch (service) {
              'chat' => l.chatModel,
              'embeddings' => l.semanticSearch,
              'images' => l.automaticImages,
              'vision' => l.photo,
              'voice' => l.voiceService,
              _ => l.automaticCritiques,
            }),
            subtitle: Text(switch (statuses[service]) {
              'demo' => l.serviceDemo,
              'available' => l.serviceAvailable,
              'configured_unchecked' => l.serviceUnchecked,
              _ => l.servicesUnavailable,
            }),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l.serviceCheckExplanation),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: FilledButton(
            onPressed: _busy || ref.watch(apiClientProvider) == null
                ? null
                : _check,
            child: Text(_busy ? l.loadingServerSettings : l.checkServices),
          ),
        ),
      ],
    );
  }
}
