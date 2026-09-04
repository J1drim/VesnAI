import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../data/library_preferences.dart';
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
import 'sync_status.dart';
import 'sticky_note_card.dart';

class NotesScreen extends ConsumerStatefulWidget {
  final bool initialGrid;
  const NotesScreen({super.key, this.initialGrid = false});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _searchController = TextEditingController();

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
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          pushed < 0 ? l.offlineChangesQueued : l.syncedChanges(pushed),
        ),
      ),
    );
  }

  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    final l = AppLocalizations.of(context);
    final locked =
        error.toString().contains('database is locked') ||
        error.toString().contains('SqliteException(5)');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              locked ? l.notesBusySyncing : l.couldNotLoadNotes,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  ref.read(notesProvider.notifier).reload(retries: 2),
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
    final grid =
        ref.watch(libraryPreferencesProvider)['grid'] as bool? ??
        widget.initialGrid;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VesnaiLogo(height: 28, full: false),
            const SizedBox(width: 8),
            Flexible(child: Text(l.navNotes, maxLines: 1, overflow: TextOverflow.ellipsis)),
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
            tooltip: grid ? l.listLayout : l.gridLayout,
            icon: Icon(
              grid ? Icons.view_list_outlined : Icons.grid_view_outlined,
            ),
            onPressed: () => ref
                .read(libraryPreferencesProvider.notifier)
                .set('grid', !grid),
          ),
          IconButton(
            tooltip: l.webSearch,
            icon: const Icon(Icons.travel_explore),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
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
          const SyncStatus(),
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
                  if (visible.isEmpty) {
                    return ListView(
                      children: [
                        SizedBox(
                          height: query.isEmpty && typeFilter.isEmpty
                              ? 200
                              : 120,
                        ),
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
                  void openNote(int index) => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          NoteDetailScreen(path: visible[index].path),
                    ),
                  );
                  if (grid) {
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 360,
                        mainAxisExtent:
                            250 *
                            MediaQuery.textScalerOf(
                              context,
                            ).scale(1).clamp(1, 2),
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, index) => StickyNoteCard(
                        note: visible[index],
                        onTap: () => openNote(index),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final note = visible[index];
                      return Dismissible(
                        key: ValueKey('dismiss-' + note.path),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) =>
                            confirmDeleteNote(context, note: note),
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
                          onTap: () => openNote(index),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CaptureScreen())),
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
