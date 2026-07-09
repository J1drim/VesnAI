import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Register TTS: a self-hosted HTTP sidecar or OpenAI (swap anytime in
/// Settings). Sidecar voice IDs are engine-specific, so they have no defaults.
class VoiceServiceScreen extends ConsumerStatefulWidget {
  const VoiceServiceScreen({super.key});

  @override
  ConsumerState<VoiceServiceScreen> createState() => _VoiceServiceScreenState();
}

class _VoiceServiceScreenState extends ConsumerState<VoiceServiceScreen> {
  String _provider = 'sidecar';
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  final _modelController = TextEditingController(text: 'tts-1');
  final _plVoiceController = TextEditingController();
  final _enVoiceController = TextEditingController();
  bool _busy = false;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _modelController.dispose();
    _plVoiceController.dispose();
    _enVoiceController.dispose();
    super.dispose();
  }

  void _applyProviderDefaults(String provider) {
    if (provider == 'openai') {
      _plVoiceController.text = 'nova';
      _enVoiceController.text = 'nova';
      _modelController.text = 'tts-1';
    } else {
      // Sidecar voice IDs depend on the engine behind it — no defaults.
      _urlController.clear();
      _plVoiceController.clear();
      _enVoiceController.clear();
    }
  }

  Future<void> _load() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    try {
      final voice = await client.getVoiceRegistration();
      if (!mounted) return;
      setState(() {
        _configured = voice['configured'] == true;
        if (_configured) {
          _provider = voice['provider']?.toString() ?? 'sidecar';
          final url = voice['url']?.toString();
          if (url != null && url.isNotEmpty) {
            _urlController.text = url;
          }
          _modelController.text = voice['model']?.toString() ?? 'tts-1';
          final voices = voice['voices'] as Map<String, dynamic>? ?? {};
          _plVoiceController.text =
              voices['pl']?.toString() ?? _plVoiceController.text;
          _enVoiceController.text =
              voices['en']?.toString() ?? _enVoiceController.text;
        }
      });
    } catch (_) {
      // Ignore; form stays at defaults.
    }
  }

  Future<void> _save() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    final l = AppLocalizations.of(context);
    if (_keyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.apiKeyRequired)),
      );
      return;
    }
    if (_provider == 'sidecar' && _urlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.sidecarUrlRequired)),
      );
      return;
    }
    if (_provider == 'sidecar' &&
        (_plVoiceController.text.trim().isEmpty ||
            _enVoiceController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.voiceIdsRequired)),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await client.putVoiceRegistration(
        provider: _provider,
        apiKey: _keyController.text,
        url: _provider == 'sidecar' ? _urlController.text.trim() : null,
        voices: {
          'pl': _plVoiceController.text.trim(),
          'en': _enVoiceController.text.trim(),
        },
        model: _provider == 'openai' ? _modelController.text.trim() : null,
      );
      _keyController.clear();
      ref.invalidate(serverSettingsProvider);
      if (mounted) {
        setState(() => _configured = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.voiceServiceRegisteredSnack)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.registrationFailed('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await client.deleteVoiceRegistration();
      ref.invalidate(serverSettingsProvider);
      if (mounted) {
        setState(() => _configured = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.voiceServiceRemoved)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.removeFailed('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOpenAi = _provider == 'openai';
    final l = AppLocalizations.of(context);
    final providers = [
      ('sidecar', l.providerTtsSidecar),
      ('openai', 'OpenAI'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.voiceService)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _configured
                ? l.voiceServiceIntroConfigured
                : l.voiceServiceIntroUnconfigured,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const Key('voice-provider'),
            value: _provider,
            decoration: InputDecoration(labelText: l.providerLabel),
            items: [
              for (final (id, label) in providers)
                DropdownMenuItem(value: id, child: Text(label)),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _provider = value;
                      if (!_configured) _applyProviderDefaults(value);
                    });
                  },
          ),
          if (!isOpenAi) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('voice-url'),
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l.sidecarUrl,
                hintText: 'http://127.0.0.1:59125',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.sidecarContractHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            key: const Key('voice-api-key'),
            controller: _keyController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: isOpenAi
                  ? (_configured ? l.openaiApiKeyUpdate : l.openaiApiKey)
                  : (_configured ? l.sidecarApiKeyUpdate : l.sidecarApiKey),
            ),
          ),
          if (isOpenAi) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: InputDecoration(
                labelText: l.openaiModel,
                hintText: 'tts-1',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _plVoiceController,
            decoration: InputDecoration(
              labelText: isOpenAi ? l.polishVoiceOpenai : l.polishVoiceId,
              hintText: isOpenAi ? 'nova' : l.voiceIdHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _enVoiceController,
            decoration: InputDecoration(
              labelText: isOpenAi ? l.englishVoiceOpenai : l.englishVoiceId,
              hintText: isOpenAi ? 'nova' : l.voiceIdHint,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('voice-save'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_configured ? l.updateRegistration : l.register),
          ),
          if (_configured) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('voice-remove'),
              onPressed: _busy ? null : _remove,
              child: Text(l.removeVoiceService),
            ),
          ],
        ],
      ),
    );
  }
}
