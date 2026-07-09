import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api_client.dart';
import '../../data/app_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'qr_scan_screen.dart';
import 'secrets_screen.dart';
import 'voice_service_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(serverConnectionProvider);
    final settings = ref.watch(serverSettingsProvider);
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        children: [
          _SectionHeader(l.sectionServer),
          ListTile(
            key: const Key('connection-tile'),
            leading: const Icon(Icons.dns_outlined),
            title: Text(l.connection),
            subtitle:
                Text(conn.isPaired ? conn.baseUrl.toString() : l.notPairedShort),
            trailing: Icon(conn.isPaired ? Icons.link : Icons.qr_code_scanner),
            onTap: () => _showPairDialog(context, ref),
          ),
          if (conn.isPaired)
            ListTile(
              key: const Key('unpair-tile'),
              leading: const Icon(Icons.link_off),
              title: Text(l.unpairDevice),
              onTap: () => _confirmUnpair(context, ref),
            ),
          _SectionHeader(l.sectionApp),
          ListTile(
            key: const Key('app-language-tile'),
            leading: const Icon(Icons.language_outlined),
            title: Text(l.appLanguage),
            subtitle: Text(_appLocaleLabel(l, ref.watch(appLocaleProvider))),
            onTap: () => _pickAppLanguage(context, ref),
          ),
          _SectionHeader(l.sectionModelsPrivacy),
          settings.when(
            loading: () => ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(l.localOnlyMode),
              subtitle: Text(l.loadingServerSettings),
            ),
            error: (e, _) => ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(l.localOnlyMode),
              subtitle: Text(l.pairToViewPrivacy),
            ),
            data: (s) => SwitchListTile(
              value: (s?['offline_only'] as bool?) ?? true,
              onChanged: null, // Server-enforced; shown read-only by design.
              secondary: const Icon(Icons.privacy_tip_outlined),
              title: Text(l.localOnlyMode),
              subtitle: Text(l.localOnlySubtitle),
            ),
          ),
          _SectionHeader(l.sectionAssistant),
          ListTile(
            key: const Key('assistant-language-tile'),
            leading: const Icon(Icons.translate_outlined),
            title: Text(l.assistantLanguage),
            subtitle: Text(
              _assistantLanguageLabel(l, ref.watch(assistantLanguageProvider)),
            ),
            onTap: () => _pickAssistantLanguage(context, ref),
          ),
          const _ReadRepliesAloudTile(),
          const _ShareLocationWithChatTile(),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: Text(l.voiceService),
            subtitle: Text(
              conn.isPaired
                  ? ((settings.valueOrNull?['voice_configured'] as bool?) ?? false
                      ? l.voiceServiceRegistered(
                          '${settings.valueOrNull?['voice_provider'] ?? 'tts'}')
                      : l.voiceServiceNotRegistered)
                  : l.voiceServicePairFirst,
            ),
            enabled: conn.isPaired,
            onTap: conn.isPaired
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const VoiceServiceScreen()),
                    )
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: Text(l.externalApiKeys),
            subtitle: Text(conn.isPaired
                ? l.externalApiKeysSubtitle
                : l.externalApiKeysPairFirst),
            enabled: conn.isPaired,
            onTap: conn.isPaired
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SecretsScreen()),
                    )
                : null,
          ),
          _SectionHeader(l.sectionModels),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: Text(l.chatModel),
            subtitle: Text(settings.valueOrNull?['default_chat_model']?.toString() ?? '-'),
          ),
          _SectionHeader(l.sectionSearch),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: Text(l.languages),
            subtitle: Text(
              (settings.valueOrNull?['search_languages'] as List?)?.join(', ') ??
                  'English, Polski',
            ),
          ),
          _SectionHeader(l.sectionData),
          ListTile(
            key: const Key('backup-tile'),
            leading: const Icon(Icons.backup_outlined),
            title: Text(l.backUpKnowledge),
            subtitle: Text(l.backUpSubtitle),
            enabled: conn.isPaired,
            onTap: conn.isPaired ? () => _backup(context, ref) : null,
          ),
          ListTile(
            key: const Key('restore-tile'),
            leading: const Icon(Icons.restore_outlined),
            title: Text(l.restoreFromBackup),
            enabled: conn.isPaired,
            onTap: conn.isPaired ? () => _restore(context, ref) : null,
          ),
        ],
      ),
    );
  }

  String _appLocaleLabel(AppLocalizations l, AppLocale locale) =>
      switch (locale) {
        AppLocale.system => l.appLanguageSystem,
        AppLocale.en => 'English',
        AppLocale.pl => 'Polski',
      };

  String _assistantLanguageLabel(AppLocalizations l, AssistantLanguage lang) =>
      switch (lang) {
        AssistantLanguage.auto => l.assistantLanguageAuto,
        AssistantLanguage.pl => 'Polski',
        AssistantLanguage.en => 'English',
      };

  Future<void> _pickAppLanguage(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final current = ref.read(appLocaleProvider);
    final picked = await showDialog<AppLocale>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.appLanguage),
        children: [
          for (final option in AppLocale.values)
            RadioListTile<AppLocale>(
              value: option,
              groupValue: current,
              title: Text(_appLocaleLabel(l, option)),
              onChanged: (value) => Navigator.pop(context, value),
            ),
        ],
      ),
    );
    if (picked != null && picked != current) {
      await ref.read(appLocaleProvider.notifier).set(picked);
    }
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final passphrase = await _askPassphrase(context, l.backupPassphraseOptional);
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    try {
      final bytes = await client.backup(
          passphrase: (passphrase != null && passphrase.isNotEmpty) ? passphrase : null);
      final ext = (passphrase != null && passphrase.isNotEmpty) ? 'zip.enc' : 'zip';
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'vesnai-backup.$ext'));
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], subject: 'VesnAI backup');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.backupFailed('$e'))));
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.pickFiles(withData: true);
    final file = result?.files.singleOrNull;
    if (file?.bytes == null) return;
    if (!context.mounted) return;
    final passphrase = file!.name.endsWith('.enc')
        ? await _askPassphrase(context, l.backupPassphraseRequired)
        : null;
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    try {
      await client.restore(file.bytes!,
          filename: file.name,
          passphrase: (passphrase != null && passphrase.isNotEmpty) ? passphrase : null);
      await ref.read(notesProvider.notifier).sync();
      messenger.showSnackBar(SnackBar(content: Text(l.restoredFromBackup)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.restoreFailed('$e'))));
    }
  }

  Future<String?> _askPassphrase(BuildContext context, String label) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(labelText: l.passphrase),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, ''), child: Text(l.skip)),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(l.ok)),
        ],
      ),
    );
  }

  Future<void> _confirmUnpair(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.unpairQuestion),
        content: Text(l.unpairExplanation),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          FilledButton(
            key: const Key('unpair-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.unpair),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(serverConnectionProvider.notifier).unpair();
    }
  }

  Future<void> _pickAssistantLanguage(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final current = ref.read(assistantLanguageProvider);
    final picked = await showDialog<AssistantLanguage>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.assistantLanguage),
        children: [
          for (final option in AssistantLanguage.values)
            RadioListTile<AssistantLanguage>(
              value: option,
              groupValue: current,
              title: Text(_assistantLanguageLabel(l, option)),
              onChanged: (value) => Navigator.pop(context, value),
            ),
        ],
      ),
    );
    if (picked != null && picked != current) {
      await ref.read(assistantLanguageProvider.notifier).set(picked);
    }
  }

  void _showPairDialog(BuildContext context, WidgetRef ref) =>
      showPairServerDialog(context, ref);
}

/// Open the pair-with-server dialog from anywhere (settings, unpaired CTA).
void showPairServerDialog(BuildContext context, WidgetRef ref) {
  final urlController = TextEditingController(
    text: ref.read(serverConnectionProvider).baseUrl?.toString() ?? 'https://',
  );
  final codeController = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (context) => _PairDialog(
      urlController: urlController,
      codeController: codeController,
      ref: ref,
    ),
  );
}

class _PairDialog extends StatefulWidget {
  final TextEditingController urlController;
  final TextEditingController codeController;
  final WidgetRef ref;
  const _PairDialog({
    required this.urlController,
    required this.codeController,
    required this.ref,
  });

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (raw == null) return;
    try {
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      widget.urlController.text = (payload['url'] ?? '') as String;
      widget.codeController.text = (payload['code'] ?? '') as String;
    } catch (_) {
      // Not JSON: treat the whole string as the code.
      widget.codeController.text = raw;
    }
    setState(() {});
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final baseUrl = Uri.parse(widget.urlController.text.trim());
      await widget.ref.read(serverConnectionProvider.notifier).pair(
            baseUrl: baseUrl,
            code: widget.codeController.text.trim(),
            deviceName: 'VesnAI app',
          );
      if (mounted) {
        final l = AppLocalizations.of(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.pairedWithServer)),
        );
      }
    } on PairingException {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).invalidCode);
      }
    } on FormatException {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).enterValidServerUrl);
      }
    } catch (e) {
      if (!mounted) return;
      setState(
          () => _error = pairingConnectionErrorMessage(e, AppLocalizations.of(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.pairDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('pair-url-field'),
            controller: widget.urlController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: l.serverUrl),
          ),
          TextField(
            key: const Key('pair-code-field'),
            controller: widget.codeController,
            // Codes are 8-char uppercase alphanumerics (no ambiguous chars).
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: l.pairingCode),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('pair-scan'),
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(l.scanQr),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('pair-submit'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.pair),
        ),
      ],
    );
  }
}

class _ReadRepliesAloudTile extends ConsumerWidget {
  const _ReadRepliesAloudTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final pref = ref.watch(readRepliesAloudProvider);
    return pref.when(
      loading: () => SwitchListTile(
        secondary: const Icon(Icons.volume_up_outlined),
        title: Text(l.readRepliesAloud),
        subtitle: Text(l.readRepliesAloudSubtitle),
        value: true,
        onChanged: null,
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (enabled) => SwitchListTile(
        key: const Key('read-replies-aloud'),
        secondary: const Icon(Icons.volume_up_outlined),
        title: Text(l.readRepliesAloud),
        subtitle: Text(l.readRepliesAloudSubtitle),
        value: enabled,
        onChanged: (v) async {
          await ref.read(appPreferencesStoreProvider).setReadRepliesAloud(v);
          ref.invalidate(readRepliesAloudProvider);
        },
      ),
    );
  }
}

class _ShareLocationWithChatTile extends ConsumerWidget {
  const _ShareLocationWithChatTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final enabled = ref.watch(shareLocationWithChatProvider);
    return SwitchListTile(
      key: const Key('share-location-with-chat'),
      secondary: const Icon(Icons.location_on_outlined),
      title: Text(l.shareLocationWithChat),
      subtitle: Text(l.shareLocationSubtitle),
      value: enabled,
      onChanged: (v) => ref.read(shareLocationWithChatProvider.notifier).set(v),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
