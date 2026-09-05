import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../note_detail/note_detail_screen.dart';

class SharedInboxScreen extends ConsumerWidget {
  const SharedInboxScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final pending = ref.watch(pendingNativeSharesProvider).valueOrNull ?? [];
    final notes = (ref.watch(notesProvider).valueOrNull ?? [])
        .where((note) => note.tags.contains('inbox'))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(l.sharedInbox),
        actions: [
          IconButton(
            tooltip: l.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              try {
                await ref.read(notesProvider.notifier).ingestSharedCaptures();
              } catch (_) {
                if (context.mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l.sharedImportRetry)));
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l.sharedInboxExplanation),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: notes.length + pending.length,
              itemBuilder: (context, index) {
                if (index < pending.length) {
                  final item = pending[index];
                  return ListTile(
                    title: Text(
                      '${l.pendingSharedImport}: ${item['title'] ?? ''}',
                    ),
                    subtitle: Text(
                      item['text'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: l.discardSharedImport,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final discard = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(l.discardSharedImport),
                            content: Text(l.discardSharedImportConfirm),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(l.cancel),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(l.discardSharedImport),
                              ),
                            ],
                          ),
                        );
                        if (discard != true || !context.mounted) return;
                        if (ref.read(sharedCaptureServiceProvider).running)
                          return;
                        try {
                          await ref
                              .read(nativeShareBridgeProvider)
                              .acknowledge(item['id'] as String);
                          ref.invalidate(pendingNativeSharesProvider);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.sharedImportRetry)),
                            );
                          }
                        }
                      },
                    ),
                  );
                }
                final note = notes[index - pending.length];
                final duplicate =
                    (note.frontmatter['vesnai'] as Map?)?['duplicate_of']
                        as String?;
                return Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(note.title),
                        subtitle: Text(note.source),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => NoteDetailScreen(path: note.path),
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: l.fileAway,
                          icon: const Icon(Icons.drive_file_move_outline),
                          onPressed: () async {
                            await ref
                                .read(notesProvider.notifier)
                                .updateNote(
                                  note.copyWith(
                                    tags: note.tags
                                        .where((tag) => tag != 'inbox')
                                        .toList(),
                                  ),
                                );
                          },
                        ),
                      ),
                      if (duplicate != null)
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => NoteDetailScreen(path: duplicate),
                            ),
                          ),
                          child: Text(l.possibleDuplicateSource),
                        ),
                    ],
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
