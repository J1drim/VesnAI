import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../note_detail/note_detail_screen.dart';

/// Deep multilingual web-search agent. Submits a query to the server, which
/// runs the agent and stores the result as an OKF note we then open.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _queryController = TextEditingController();
  final Set<String> _languages = {'en', 'pl'};
  double _maxSeconds = 60;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final job = await client.search(
        query,
        languages: _languages.toList(),
        maxSeconds: _maxSeconds,
      );
      if (job['status'] == 'failed') {
        setState(() => _error = (job['error'] as String?) ?? l.searchFailed);
        return;
      }
      final path = (job['result'] as Map?)?['research'] as String?;
      // Pull the new research note into the local mirror.
      await ref.read(notesProvider.notifier).sync();
      await ref
          .read(notifierProvider)
          .jobComplete(l.researchReady, l.researchReadyBody);
      if (!mounted) return;
      if (path != null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => NoteDetailScreen(path: path)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l.searchFailedWithError('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paired = ref.watch(serverConnectionProvider).isPaired;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.webSearch)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!paired)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(l.pairForWebSearch),
              ),
            TextField(
              key: const Key('search-query'),
              controller: _queryController,
              enabled: paired && !_busy,
              decoration: InputDecoration(
                labelText: l.researchPrompt,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _run(),
            ),
            const SizedBox(height: 16),
            Text(l.languages, style: Theme.of(context).textTheme.labelLarge),
            Wrap(
              spacing: 8,
              children: [
                for (final lang in const ['en', 'pl', 'de', 'fr', 'es'])
                  FilterChip(
                    label: Text(lang.toUpperCase()),
                    selected: _languages.contains(lang),
                    onSelected: (sel) => setState(() {
                      sel ? _languages.add(lang) : _languages.remove(lang);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(l.timeBudget(_maxSeconds.round()),
                style: Theme.of(context).textTheme.labelLarge),
            Slider(
              value: _maxSeconds,
              min: 15,
              max: 180,
              divisions: 11,
              label: '${_maxSeconds.round()}s',
              onChanged: _busy ? null : (v) => setState(() => _maxSeconds = v),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('search-run'),
              onPressed: (paired && !_busy) ? _run : null,
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.travel_explore),
              label: Text(_busy ? l.researching : l.searchAction),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
