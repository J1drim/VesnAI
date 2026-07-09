import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'note_type_ui.dart';

class NotesTypeFilterBar extends ConsumerWidget {
  const NotesTypeFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(notesTypeFilterProvider);
    final notifier = ref.read(notesTypeFilterProvider.notifier);
    final showDone = ref.watch(showDoneNotesProvider);
    final showingAll = notesFilterShowsAll(selected, showDone);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              key: const Key('show-all-filter'),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.select_all, size: 16),
                  const SizedBox(width: 6),
                  Text(AppLocalizations.of(context).filterAll),
                ],
              ),
              selected: showingAll,
              onSelected: (v) {
                notifier.state = {};
                ref.read(showDoneNotesProvider.notifier).state = v;
              },
            ),
          ),
          for (final type in kUserNoteTypes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: NoteTypeFilterChip(
                type: type,
                selected: selected.contains(type),
                onSelected: (_) {
                  final next = Set<String>.from(selected);
                  if (next.contains(type)) {
                    next.remove(type);
                  } else {
                    next.add(type);
                  }
                  notifier.state = next;
                  // Picking a specific type leaves "All" mode.
                  if (showingAll) {
                    ref.read(showDoneNotesProvider.notifier).state = false;
                  }
                },
              ),
            ),
          FilterChip(
            key: const Key('show-done-filter'),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 16),
                const SizedBox(width: 6),
                Text(AppLocalizations.of(context).showDone),
              ],
            ),
            selected: showDone,
            onSelected: (v) =>
                ref.read(showDoneNotesProvider.notifier).state = v,
          ),
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(
                onPressed: () {
                  notifier.state = {};
                  ref.read(showDoneNotesProvider.notifier).state = false;
                },
                child: Text(AppLocalizations.of(context).clearFilters),
              ),
            ),
        ],
      ),
    );
  }
}
