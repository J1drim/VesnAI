import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/note.dart';
import '../../theme.dart';
import 'note_preview.dart';
import 'note_type_ui.dart';

class StickyNoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback? onTap;
  const StickyNoteCard({super.key, required this.note, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = noteTypeStyle(note.type, theme.colorScheme);
    final l = AppLocalizations.of(context);
    return Card(
      key: ValueKey('sticky-${note.path}'),
      margin: EdgeInsets.zero,
      color: Color.alphaBlend(
        (note.isGenerated ? VesnaiTheme.generatedAccent : style.fill)
            .withValues(alpha: 0.18),
        theme.colorScheme.surfaceContainerLow,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(style.icon, size: 20, color: style.color),
                  const Spacer(),
                  if (note.pinned) const Icon(Icons.push_pin, size: 18),
                  if (note.isPending)
                    const Icon(Icons.cloud_upload_outlined, size: 18),
                  if (note.isGenerated)
                    const Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: VesnaiTheme.generatedAccent,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                note.title.isEmpty ? l.untitled : note.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  notePreviewBody(note),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (note.tags.isNotEmpty)
                Text(
                  '${note.tags.take(2).map((t) => '#$t').join('  ')}${note.tags.length > 2 ? '  +${note.tags.length - 2}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
