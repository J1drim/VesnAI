import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/note.dart';

/// Confirmation before deleting a note (swipe or detail screen).
Future<bool> confirmDeleteNote(BuildContext context, {Note? note}) async {
  final title = note?.title.trim();
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.deleteNoteQuestion),
      content: Text(
        title != null && title.isNotEmpty
            ? l.deleteNoteConfirm(title)
            : l.deleteNoteSyncNote,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('delete-note-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.delete),
        ),
      ],
    ),
  );
  return ok ?? false;
}
