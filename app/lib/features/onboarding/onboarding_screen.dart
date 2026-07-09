import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/server_discovery.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../widgets/vesnai_logo.dart';
import '../settings/qr_scan_screen.dart';

/// First-run flow: discover or enter a server, pair, or continue offline.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _urlController = TextEditingController(text: 'https://');
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (raw == null) return;
    try {
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      _urlController.text = (payload['url'] ?? '') as String;
      _codeController.text = (payload['code'] ?? '') as String;
    } catch (_) {
      _codeController.text = raw;
    }
    setState(() {});
  }

  Future<void> _pair() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(serverConnectionProvider.notifier).pair(
            baseUrl: Uri.parse(_urlController.text.trim()),
            code: _codeController.text.trim(),
            deviceName: 'VesnAI app',
          );
      await completeOnboarding(ref);
    } on PairingException {
      if (!mounted) return;
      setState(() => _error = AppLocalizations.of(context).invalidCode);
    } on FormatException {
      if (!mounted) return;
      setState(() => _error = AppLocalizations.of(context).enterValidServerUrl);
    } catch (e) {
      if (!mounted) return;
      setState(
          () => _error = pairingConnectionErrorMessage(e, AppLocalizations.of(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    await completeOnboarding(ref);
  }

  @override
  Widget build(BuildContext context) {
    final discovered = ref.watch(discoveredServersProvider);
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: VesnaiLogo.brandCream,
      appBar: AppBar(
        backgroundColor: VesnaiLogo.brandCream,
        elevation: 0,
        title: const VesnaiLogo(height: 40, full: false),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(child: VesnaiLogo(height: 160)),
          const SizedBox(height: 16),
          Text(l.onboardingTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l.onboardingBody),
          const SizedBox(height: 16),
          _DiscoveredList(
            discovered: discovered,
            onPick: (s) => setState(() => _urlController.text = s.baseUrl.toString()),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('onboard-url'),
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
                labelText: l.serverUrl, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('onboard-code'),
            controller: _codeController,
            // Codes are 8-char uppercase alphanumerics (no ambiguous chars).
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
                labelText: l.pairingCode, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('onboard-scan'),
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(l.scanQr),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('onboard-pair'),
            onPressed: _busy ? null : _pair,
            child: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.pair),
          ),
          TextButton(
            key: const Key('onboard-skip'),
            onPressed: _busy ? null : _skip,
            child: Text(l.continueOffline),
          ),
        ],
      ),
    );
  }
}

class _DiscoveredList extends StatelessWidget {
  final AsyncValue<List<DiscoveredServer>> discovered;
  final void Function(DiscoveredServer) onPick;
  const _DiscoveredList({required this.discovered, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return discovered.maybeWhen(
      data: (servers) {
        if (servers.isEmpty) {
          return ListTile(
            leading: const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            title: Text(l.searchingNetwork),
            dense: true,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.foundOnNetwork,
                style: Theme.of(context).textTheme.labelLarge),
            for (final s in servers)
              ListTile(
                key: Key('discovered-${s.name}'),
                leading: const Icon(Icons.dns_outlined),
                title: Text(s.name),
                subtitle: Text(s.baseUrl.toString()),
                onTap: () => onPick(s),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
