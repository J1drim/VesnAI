import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../note_detail/note_detail_screen.dart';
import '../../widgets/vesnai_logo.dart';
import '../capture/capture_screen.dart';
import '../search/search_screen.dart';
import 'delete_note_dialog.dart';
import '../../widgets/unpaired_banner.dart';
import 'note_preview.dart';
import 'note_search.dart';
import 'note_tile.dart';
import 'note_type_ui.dart';
import 'notes_type_filter.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _searchController = TextEditingController();
  List<({String path, String? title})> _dueNotes = const [];
  bool _dueLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDueNotes());
  }

  Future<void> _loadDueNotes() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    setState(() => _dueLoading = true);
    try {
      final due = await client.listDueNotes();
      if (mounted) setState(() => _dueNotes = due);
    } catch (_) {
      // Due notes are optional UX — ignore offline errors.
    } finally {
      if (mounted) setState(() => _dueLoading = false);
    }
  }

  Future<void> _openDueNote(({String path, String? title}) due) async {
    final client = ref.read(apiClientProvider);
    if (client != null) {
      unawaited(client.markNoteResurfaced(due.path));
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteDetailScreen(path: due.path)),
    );
    _loadDueNotes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final pushed = await ref.read(notesProvider.notifier).sync();
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
          pushed < 0 ? l.offlineChangesQueued : l.syncedChanges(pushed)),
    ));
  }

  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    final l = AppLocalizations.of(context);
    final locked = error.toString().contains('database is locked') ||
        error.toString().contains('SqliteException(5)');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(
              locked ? l.notesBusySyncing : l.couldNotLoadNotes,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(notesProvider.notifier).reload(retries: 2),
              child: Text(l.retry),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider);
    final lastSynced = ref.watch(lastSyncedProvider);
    final paired = ref.watch(serverConnectionProvider).isPaired;
    final l = AppLocalizations.of(context);
    final query = _searchController.text;
    final typeFilter = ref.watch(notesTypeFilterProvider);
    final showDone = ref.watch(showDoneNotesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VesnaiLogo(height: 28, full: false),
            const SizedBox(width: 8),
            Text(l.navNotes),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              paired
                  ? (lastSynced == null
                      ? l.pairedPullToSync
                      : l.lastSynced(_ago(context, lastSynced)))
                  : l.notPaired,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: l.webSearch,
            icon: const Icon(Icons.travel_explore),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            tooltip: l.sync,
            icon: const Icon(Icons.sync),
            onPressed: () => _sync(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          const UnpairedBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l.searchNotesHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const NotesTypeFilterBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _sync(context, ref),
              child: notes.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _errorView(context, ref, e),
                data: (list) {
                  final visible = list
                      .where(noteVisibleInMainList)
                      .where((n) => showDone || !n.done)
                      .where((n) => noteMatchesTypeFilter(n, typeFilter))
                      .where((n) => noteMatchesQuery(n, query))
                      .toList();
                  if (visible.isEmpty && (_dueNotes.isEmpty || query.isNotEmpty || typeFilter.isNotEmpty)) {
                    return ListView(
                      children: [
                        SizedBox(height: query.isEmpty && typeFilter.isEmpty ? 200 : 120),
                        Center(
                          child: Text(
                            query.isNotEmpty
                                ? l.noNotesMatchQuery(query)
                                : typeFilter.isNotEmpty
                                    ? l.noNotesMatchTypes
                                    : l.emptyNotes,
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView(
                    children: [
                      if (_dueNotes.isNotEmpty && query.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            children: [
                              const Icon(Icons.schedule, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                l.dueForReview,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if (_dueLoading) ...[
                                const SizedBox(width: 8),
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ..._dueNotes.map(
                          (due) => ListTile(
                            leading: const Icon(Icons.replay_outlined),
                            title: Text(due.title ?? due.path),
                            subtitle: Text(
                              due.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _openDueNote(due),
                          ),
                        ),
                        const Divider(height: 24),
                      ],
                      ...visible.map(
                        (note) => Dismissible(
                          key: ValueKey('dismiss-${note.path}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => confirmDeleteNote(context, note: note),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: const Icon(Icons.delete_outline),
                          ),
                          onDismissed: (_) =>
                              ref.read(notesProvider.notifier).delete(note.path),
                          child: NoteTile(
                            note: note,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => NoteDetailScreen(path: note.path),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CaptureScreen()),
        ),
        icon: const Icon(Icons.add),
        label: Text(l.capture),
      ),
    );
  }

  String _ago(BuildContext context, DateTime t) {
    final l = AppLocalizations.of(context);
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return l.justNow;
    if (d.inHours < 1) return l.minutesAgo(d.inMinutes);
    if (d.inDays < 1) return l.hoursAgo(d.inHours);
    return l.daysAgo(d.inDays);
  }
}
