import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../models/note.dart';
import '../../providers.dart';
import 'note_type_ui.dart';

class LibraryControls extends ConsumerWidget {
  final String query;
  final ValueChanged<String> onQuery;
  const LibraryControls({
    super.key,
    required this.query,
    required this.onQuery,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final prefs = ref.watch(libraryPreferencesProvider);
    final controller = ref.read(libraryPreferencesProvider.notifier);
    final scope = prefs['scope'] ?? 'active';
    final tag = prefs['tag'] as String? ?? '';
    final saved = (prefs['views'] as List? ?? []).cast<Map>();
    final tags =
        (ref.watch(notesProvider).valueOrNull ?? <Note>[])
            .expand((n) => n.tags)
            .toSet()
            .toList()
          ..sort();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          for (final item in [
            ('active', l.libraryActive),
            ('pinned', l.pinnedNotes),
            ('archive', l.archive),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(item.$2),
                selected: scope == item.$1,
                onSelected: (_) => controller.set('scope', item.$1),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: l.filterTags,
            onSelected: (value) => controller.set('tag', value),
            itemBuilder: (_) => [
              PopupMenuItem(value: '', child: Text(l.filterAll)),
              for (final value in tags)
                PopupMenuItem(value: value, child: Text('#$value')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(tag.isEmpty ? l.filterTags : '#$tag'),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: l.sortNotes,
            icon: const Icon(Icons.sort),
            onSelected: (value) => controller.set('sort', value),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'updated', child: Text(l.sortRecent)),
              PopupMenuItem(value: 'oldest', child: Text(l.sortOldest)),
              PopupMenuItem(value: 'title', child: Text(l.titleLabel)),
            ],
          ),
          PopupMenuButton<int>(
            tooltip: l.savedViews,
            icon: const Icon(Icons.bookmarks_outlined),
            onSelected: (index) async {
              if (index == -1) {
              var name = '';
                final accepted = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l.saveView),
                    content: TextField(
                    onChanged: (value) => name = value,
                      autofocus: true,
                      decoration: InputDecoration(labelText: l.titleLabel),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(l.cancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(l.save),
                      ),
                    ],
                  ),
                );
              final title = name.trim();
                if (accepted == true && title.isNotEmpty) {
                  await controller.set('views', [
                    ...saved.where((v) => v['name'] != title),
                    {
                      'name': title,
                      'query': query,
                      'scope': scope,
                      'tag': tag,
                      'sort': prefs['sort'] ?? 'updated',
                      'types': ref.read(notesTypeFilterProvider).toList(),
                      'done': ref.read(showDoneNotesProvider),
                    },
                  ]);
                }
                return;
              }
              if (index < -1) {
                await controller.set('views', [...saved]..removeAt(-index - 2));
                return;
              }
              final view = saved[index];
              for (final key in ['scope', 'tag', 'sort']) {
                await controller.set(key, view[key]);
              }
              ref.read(notesTypeFilterProvider.notifier).state =
                  (view['types'] as List).cast<String>().toSet();
              ref.read(showDoneNotesProvider.notifier).state =
                  view['done'] == true;
              onQuery(view['query'] as String? ?? '');
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: -1, child: Text(l.saveView)),
              for (var i = 0; i < saved.length; i++) ...[
                PopupMenuItem(
                  value: i,
                  child: Text(saved[i]['name'] as String),
                ),
                PopupMenuItem(
                  value: -i - 2,
                  child: Text('${l.delete}: ${saved[i]['name']}'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
