import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_preferences.dart';
import '../../data/note_filter.dart';
import '../../l10n/app_localizations.dart';
import '../../models/note.dart';
import '../../providers.dart';
import '../note_detail/note_detail_screen.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final views =
        (ref.watch(libraryPreferencesProvider)['views'] as List? ?? [])
            .cast<Map>();
    return Scaffold(
      appBar: AppBar(title: Text(l.projects)),
      body: views.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.projectsExplanation),
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.projectsExplanation),
                ),
                for (final view in views)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(view['name'] as String),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ProjectScreen(view: view.cast<String, dynamic>()),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class ProjectScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> view;
  const ProjectScreen({super.key, required this.view});
  @override
  ConsumerState<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends ConsumerState<ProjectScreen> {
  final _question = TextEditingController();
  List<Note> _notes = [];
  List<Map<String, dynamic>> _turns = [];
  bool _loading = true;
  bool _asking = false;
  String? _error;
  String get _key =>
      'project_chat:${sha256.convert(utf8.encode(jsonEncode(widget.view)))}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<List<Note>> _scope() {
    final v = widget.view;
    return ref
        .read(localStoreProvider)
        .search(
          v['query'] as String? ?? '',
          limit: 10000,
          filter: NoteFilter(
            scope: v['scope'] as String? ?? 'active',
            tag: v['tag'] as String? ?? '',
            sort: v['sort'] as String? ?? 'updated',
            types: (v['types'] as List? ?? []).cast<String>().toSet(),
            showDone: v['done'] == true,
            libraryOnly: true,
          ),
        );
  }

  Future<void> _load() async {
    try {
      final notes = await _scope();
      final turns =
          (jsonDecode(
                    await ref.read(localStoreProvider).localValue(_key) ?? '[]',
                  )
                  as List)
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
      if (mounted)
        setState(() {
          _notes = notes;
          _turns = turns;
          _loading = false;
          _error = null;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '$error';
          _loading = false;
        });
    }
  }

  Future<void> _ask() async {
    final question = _question.text.trim();
    if (_asking || question.isEmpty) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _asking = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      if (client == null) throw StateError(l.projectAnswerUnavailable);
      final notes = await _scope();
      // Unsent local edits are not falsely represented as server evidence.
      if (notes.any((n) => n.isPending))
        throw StateError(l.syncBeforeProjectQuestion);
      final response = await client.libraryRecovery(
        'ask',
        method: 'POST',
        body: {
          'question': question,
          'view': widget.view,
          'paths': notes.map((n) => n.path).toList(),
          'previous_questions': _turns.reversed
              .take(4)
              .map((t) => t['question'])
              .toList()
              .reversed
              .toList(),
        },
      );
      if (response['available'] != true)
        throw StateError(l.projectAnswerUnavailable);
      final turns = [
        ..._turns,
        {
          'question': question,
          'answer': response['scope_empty'] == true
              ? l.projectScopeEmpty
              : response['answer'],
          'sources': response['sources'],
          'context_count': response['context_count'],
          'scope_count': response['scope_count'],
        },
      ];
      // Bound device-local conversation storage; all notes remain in the library.
      final retained = turns.length > 100
          ? turns.sublist(turns.length - 100)
          : turns;
      final store = ref.read(localStoreProvider);
      await store.transaction(
        () => store.setLocalValue(_key, jsonEncode(retained)),
      );
      if (mounted)
        setState(() {
          _notes = notes;
          _turns = retained;
          _question.clear();
        });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  void _open(String path) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => NoteDetailScreen(path: path)),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.view['name'] as String),
        actions: [
          IconButton(
            tooltip: l.refresh,
            onPressed: _asking ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      l.projectCounts(
                        _notes.length,
                        _notes.where((n) => n.type == 'Task' && !n.done).length,
                        _notes.where((n) => n.type == 'Research').length,
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    ExpansionTile(
                      title: Text(l.navNotes),
                      initiallyExpanded: true,
                      children: [
                        for (final note in _notes.take(100))
                          ListTile(
                            title: Text(note.title),
                            subtitle: Text(note.type),
                            onTap: () => _open(note.path),
                          ),
                        if (_notes.length > 100)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(l.projectFirstHundred),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.askProject,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(l.projectQuestionExplanation),
                    for (final turn in _turns)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                turn['question'] as String,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              SelectableText(turn['answer'] as String? ?? ''),
                              if (turn['context_count'] != null)
                                Text(
                                  l.projectEvidenceCount(
                                    turn['context_count'] as int,
                                    turn['scope_count'] as int,
                                  ),
                                ),
                              for (final source
                                  in turn['sources'] as List? ?? [])
                                TextButton(
                                  onPressed: () =>
                                      _open(source['path'] as String),
                                  child: Text(
                                    '[${source['index']}] ${source['title']}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    TextField(
                      controller: _question,
                      enabled: !_asking,
                      maxLength: 4000,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(labelText: l.askProject),
                      onSubmitted: (_) => _ask(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _asking ? null : _ask,
                        icon: _asking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_outlined),
                        label: Text(l.askProject),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
