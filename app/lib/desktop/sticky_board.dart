import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/notes/note_preview.dart';
import '../features/notes/note_search.dart';
import '../features/notes/note_type_ui.dart';
import '../features/notes/notes_type_filter.dart';
import '../l10n/app_localizations.dart';
import '../models/note.dart';
import '../providers.dart';
import '../theme.dart';

/// Desktop "sticky-notes" layout: notes laid out as a wrapping board of cards,
/// reusing the same data layer as mobile. Designed for the macOS/Windows builds.
class StickyBoard extends ConsumerStatefulWidget {
  const StickyBoard({super.key});

  @override
  ConsumerState<StickyBoard> createState() => _StickyBoardState();
}

class _StickyBoardState extends ConsumerState<StickyBoard> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider);
    final query = _searchController.text;
    final typeFilter = ref.watch(notesTypeFilterProvider);
    final showDone = ref.watch(showDoneNotesProvider);
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.newSticky,
            onPressed: () => ref.read(notesProvider.notifier).capture(
                  title: l.newNote,
                  body: '',
                ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
            child: notes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(l.errorWithDetail('$e'))),
              data: (list) {
                final visible = list
                    .where(noteVisibleInMainList)
                    .where((n) => showDone || !n.done)
                    .where((n) => noteMatchesTypeFilter(n, typeFilter))
                    .where((n) => noteMatchesQuery(n, query))
                    .toList();
                if (visible.isEmpty) {
                  return Center(
                    child: Text(
                      query.isNotEmpty
                          ? l.noNotesMatchQuery(query)
                          : typeFilter.isNotEmpty
                              ? l.noNotesMatchTypes
                              : l.noNotesYet,
                    ),
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [for (final note in visible) StickyNoteCard(note: note)],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class StickyNoteCard extends StatelessWidget {
  final Note note;
  const StickyNoteCard({super.key, required this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = noteTypeStyle(note.type, theme.colorScheme);
    final color = note.isGenerated
        ? VesnaiTheme.generatedAccent.withValues(alpha: 0.12)
        : style.fill.withValues(alpha: 0.35);
    return Container(
      key: ValueKey('sticky-${note.path}'),
      width: 200,
      height: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(blurRadius: 6, offset: Offset(0, 3), color: Colors.black12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                style.icon,
                size: 14,
                color: note.isGenerated ? VesnaiTheme.generatedAccent : style.color,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  note.title.isEmpty
                      ? AppLocalizations.of(context).untitled
                      : note.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (note.isGenerated)
                const Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: VesnaiTheme.generatedAccent,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(note.body, maxLines: 7, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
