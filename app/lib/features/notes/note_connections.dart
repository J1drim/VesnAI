import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local_graph.dart';
import '../../l10n/app_localizations.dart';
import '../../models/note.dart';
import '../../providers.dart';
import '../note_detail/note_detail_screen.dart';
import 'semantic_search_screen.dart';

class NoteConnections extends ConsumerWidget {
  final Note note;
  const NoteConnections({super.key, required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final all = ref.watch(notesProvider).valueOrNull ?? <Note>[];
    final edges = buildLocalGraph(all)['edges'] as List;
    final incoming = edges
        .where((e) => e['target'] == note.path)
        .map((e) => e['source'])
        .toSet();
    final outgoing = edges
        .where((e) => e['source'] == note.path)
        .map((e) => e['target'])
        .toSet();
    final query = '${note.title}\n${note.body}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        for (final group in [
          (l.backlinks, incoming),
          (l.linkedNotes, outgoing),
        ]) ...[
          if (group.$2.isNotEmpty)
            Text(group.$1, style: Theme.of(context).textTheme.titleSmall),
          for (final target in all.where((n) => group.$2.contains(n.path)))
            ListTile(
              dense: true,
              leading: const Icon(Icons.link),
              title: Text(
                target.title.isEmpty ? l.untitled : target.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NoteDetailScreen(path: target.path),
                ),
              ),
            ),
        ],
        TextButton.icon(
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(l.findRelatedNotes),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SemanticSearchScreen(
                query: query.substring(0, query.length.clamp(0, 2000)),
                sourcePath: note.path,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
