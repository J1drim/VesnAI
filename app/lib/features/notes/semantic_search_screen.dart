import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/note.dart';
import '../../providers.dart';
import '../note_detail/note_detail_screen.dart';
import 'note_tile.dart';

class SemanticSearchScreen extends ConsumerStatefulWidget {
  final String query;
  final String sourcePath;
  final List<String>? paths;
  const SemanticSearchScreen({
    super.key,
    this.query = '',
    this.sourcePath = '',
    this.paths,
  });
  @override
  ConsumerState<SemanticSearchScreen> createState() => _SemanticSearchState();
}

class _SemanticSearchState extends ConsumerState<SemanticSearchScreen> {
  late final _query = TextEditingController(text: widget.query);
  List<Note> _results = [];
  bool _busy = false;
  bool _unavailable = false;
  bool _searched = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final client = ref.read(apiClientProvider);
    if (client == null || _query.text.trim().isEmpty) {
      setState(() => _unavailable = true);
      return;
    }
    setState(() {
      _busy = true;
      _unavailable = false;
    });
    try {
      final result = await client.searchLibrary(
        _query.text.trim(),
        excludePath: widget.sourcePath,
        paths: widget.paths,
      );
      if (!mounted) return;
      setState(() {
        _unavailable = result['available'] != true;
        _results = (result['results'] as List)
            .map(
              (r) => Note.fromApi((r['note'] as Map).cast<String, dynamic>()),
            )
            .toList();
        _searched = true;
      });
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Note note) async {
    final store = ref.read(localStoreProvider);
    await store.transaction(() async {
      final local = await store.get(note.path);
      if (local == null || (!local.isPending && local.version <= note.version))
        await store.put(note);
    });
    await ref.read(notesProvider.notifier).reload();
    if (mounted)
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NoteDetailScreen(path: note.path)),
      );
  }

  Future<void> _link(Note note) async {
    final source = await ref.read(localStoreProvider).get(widget.sourcePath);
    if (source == null) return;
    await ref
        .read(notesProvider.notifier)
        .updateNote(
          source.copyWith(links: {...source.links, note.path}.toList()),
        );
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).linkedNote)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.semanticSearch)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l.semanticSearchExplanation),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _query,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(hintText: l.searchNotesHint),
                  onSubmitted: (_) => _search(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _search,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(l.semanticSearch),
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_unavailable)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.semanticUnavailable),
                ),
              if (_searched && !_unavailable && _results.isEmpty)
                Text(l.noRelatedNotes),
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final note = _results[i];
                    return Column(
                      children: [
                        NoteTile(note: note, onTap: () => _open(note)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l.similarMeaning,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                              if (widget.sourcePath.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () => _link(note),
                                  icon: const Icon(Icons.add_link),
                                  label: Text(l.linkNote),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
