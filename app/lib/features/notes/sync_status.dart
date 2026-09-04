import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:okf_dart/okf_dart.dart';

import '../../l10n/app_localizations.dart';
import '../../models/note.dart';
import '../../providers.dart';

final pendingNotesProvider = FutureProvider<List<Note>>((ref) async {
  ref.watch(notesProvider);
  return ref.watch(localStoreProvider).pending();
});

/// Queue failures are visible even when the affected note is filtered out.
class SyncStatus extends ConsumerWidget {
  const SyncStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingNotesProvider).valueOrNull ?? <Note>[];
    if (pending.isEmpty) return const SizedBox.shrink();
    final conflicts = pending
        .where((n) => n.syncState == SyncState.conflict)
        .toList();
    final l = AppLocalizations.of(context);
    return ListTile(
      dense: true,
      leading: Icon(
        conflicts.isEmpty ? Icons.cloud_upload_outlined : Icons.sync_problem,
      ),
      title: Text('${pending.length} · ${l.pendingChanges}'),
      subtitle: conflicts.isEmpty ? null : Text(l.syncConflictTitle),
      trailing: TextButton(
        onPressed: () async {
          if (conflicts.isEmpty) {
            await ref.read(notesProvider.notifier).sync();
          } else {
            await showConflictRecovery(context, ref, conflicts.first);
          }
        },
        child: Text(conflicts.isEmpty ? l.retry : l.resolveConflict),
      ),
    );
  }
}

Future<void> showConflictRecovery(
  BuildContext context,
  WidgetRef ref,
  Note note,
) async {
  final l = AppLocalizations.of(context);
  var server = note.serverDoc;
  try {
    final concept = parseConcept(server);
    server = '${concept.frontmatter['title'] ?? ''}\n\n${concept.body}';
  } catch (_) {
    // Older servers may return only an error, not a document snapshot.
  }
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.syncConflictTitle),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.syncConflictExplanation),
              const SizedBox(height: 16),
              Text(l.keepMine, style: Theme.of(context).textTheme.titleSmall),
              SelectableText(
                note.conflictDeleted
                    ? l.delete
                    : '${note.title}\n\n${note.body}',
              ),
              const Divider(height: 32),
              Text(l.keepServer, style: Theme.of(context).textTheme.titleSmall),
              SelectableText(server.isEmpty ? l.serverNoteUnavailable : server),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'server'),
          child: Text(l.keepServer),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'mine'),
          child: Text(l.keepMine),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'both'),
          child: Text(l.keepBoth),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  try {
    await ref.read(syncEngineProvider).resolveConflict(note.path, choice);
    await ref.read(notesProvider.notifier).sync();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.offlineChangesQueued)));
    }
  }
}
