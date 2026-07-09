import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Manage external API keys stored (encrypted) on the server. Values are
/// write-only: the server returns names only, never the secret values.
class SecretsScreen extends ConsumerWidget {
  const SecretsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(serverSettingsProvider);
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.externalApiKeys)),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.errorWithDetail('$e'))),
        data: (s) {
          final names = ((s?['secret_names'] ?? const []) as List).cast<String>();
          if (names.isEmpty) {
            return Center(child: Text(l.noApiKeysStored));
          }
          return ListView(
            children: [
              for (final name in names)
                ListTile(
                  key: Key('secret-$name'),
                  leading: const Icon(Icons.key),
                  title: Text(name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await ref.read(apiClientProvider)?.deleteSecret(name);
                      ref.invalidate(serverSettingsProvider);
                    },
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('add-secret'),
        onPressed: () => _addSecret(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addSecret(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    final l = AppLocalizations.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.addApiKey),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('secret-name'),
              controller: nameController,
              decoration: InputDecoration(labelText: l.apiKeyNameLabel),
            ),
            TextField(
              key: const Key('secret-value'),
              controller: valueController,
              obscureText: true,
              decoration: InputDecoration(labelText: l.apiKeyValueLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          FilledButton(
            key: const Key('secret-save'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.save),
          ),
        ],
      ),
    );
    if (saved == true && nameController.text.trim().isNotEmpty) {
      await ref.read(apiClientProvider)?.setSecret(
            nameController.text.trim(),
            valueController.text,
          );
      ref.invalidate(serverSettingsProvider);
    }
  }
}
