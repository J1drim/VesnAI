import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/note.dart';
import '../../theme.dart';
import 'note_preview.dart';
import 'note_type_ui.dart';

/// A single note card. AI-generated notes carry a clear visual badge so the
/// user can always distinguish their own content from VesnAI's.
class NoteTile extends StatelessWidget {
  final Note note;
  final VoidCallback? onTap;

  const NoteTile({super.key, required this.note, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = noteTypeStyle(note.type, theme.colorScheme);
    // Keep Marena's recognizable accent, with neutral reading surfaces.
    final isCritique = note.type == kCritiqueNoteType;
    final l = AppLocalizations.of(context);
    final semanticLabel = [
      note.type,
      note.isGenerated ? l.aiGenerated : l.yourNote,
      note.title.isEmpty ? l.untitledPlain : note.title,
      if (note.done) l.doneLabel,
      if (note.isPending) l.pendingSyncLabel,
    ].join(', ');
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: Card(
        key: ValueKey('note-${note.path}'),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: note.isGenerated && !isCritique
                ? VesnaiTheme.generatedAccent.withValues(alpha: 0.18)
                : style.fill.withValues(alpha: 0.35),
            child: Icon(
              style.icon,
              color: note.isGenerated && !isCritique
                  ? VesnaiTheme.generatedAccent
                  : style.color,
            ),
          ),
          title: Text(
            note.title.isEmpty ? l.untitled : note.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: note.done
                ? TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notePreviewBody(note),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (note.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${note.tags.take(3).map((t) => '#$t').join('  ')}${note.tags.length > 3 ? '  +${note.tags.length - 3}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (note.pinned) const Icon(Icons.push_pin, size: 16),
              if (isCritique)
                _Badge(label: 'Marena', color: style.color, icon: style.icon)
              else if (note.isGenerated)
                _Badge(
                  label: 'AI',
                  color: VesnaiTheme.generatedAccent,
                  icon: Icons.auto_awesome,
                ),
              if (note.done)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _Badge(
                    label: AppLocalizations.of(context).done,
                    color: theme.colorScheme.primary,
                    icon: Icons.check_circle,
                  ),
                ),
              if (note.isPending)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.cloud_upload_outlined, size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _Badge({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
