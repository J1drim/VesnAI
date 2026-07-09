import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/note.dart';
import '../../theme.dart';

const kUserNoteTypes = ['Note', 'Idea', 'Task', 'Photo'];

/// Notes written by the Marena critic agent (adversarial review of user notes).
const kCritiqueNoteType = 'Critique';

/// Normalizes note type strings from frontmatter (empty → Note).
String normalizeNoteType(String? type) {
  final trimmed = (type ?? '').trim();
  return trimmed.isEmpty ? 'Note' : trimmed;
}

/// Display label for a note type in the current locale. Types are stored
/// canonically in English; only the label is translated.
String localizedNoteType(BuildContext context, String type) {
  final l = AppLocalizations.of(context);
  switch (normalizeNoteType(type)) {
    case 'Note':
      return l.typeNote;
    case 'Idea':
      return l.typeIdea;
    case 'Task':
      return l.typeTask;
    case 'Photo':
      return l.typePhoto;
    case kCritiqueNoteType:
      return l.typeCritique;
    default:
      return normalizeNoteType(type);
  }
}

class NoteTypeStyle {
  final IconData icon;
  /// Icon foreground and readable label on [fill].
  final Color color;
  /// Graph node fill / strong type accent.
  final Color fill;

  const NoteTypeStyle({
    required this.icon,
    required this.color,
    required this.fill,
  });
}

NoteTypeStyle noteTypeStyle(String type, ColorScheme scheme) {
  switch (VesnaiTypePalette.bucket(normalizeNoteType(type))) {
    case 'Idea':
      return const NoteTypeStyle(
        icon: Icons.lightbulb_outline,
        color: VesnaiTypePalette.ideaIcon,
        fill: VesnaiTypePalette.ideaFill,
      );
    case 'Task':
      return const NoteTypeStyle(
        icon: Icons.task_alt,
        color: VesnaiTypePalette.taskIcon,
        fill: VesnaiTypePalette.taskFill,
      );
    case 'Photo':
      return const NoteTypeStyle(
        icon: Icons.photo_camera_outlined,
        color: VesnaiTypePalette.photoIcon,
        fill: VesnaiTypePalette.photoFill,
      );
    case kCritiqueNoteType:
      return const NoteTypeStyle(
        icon: Icons.gavel_outlined,
        color: VesnaiTypePalette.critiqueIcon,
        fill: VesnaiTypePalette.critiqueFill,
      );
    default:
      return NoteTypeStyle(
        icon: Icons.edit_note,
        color: VesnaiTypePalette.noteIcon(scheme),
        fill: VesnaiTypePalette.noteFill(scheme),
      );
  }
}

/// Readable label text on a node filled with [noteTypeStyle].fill.
Color noteTypeLabelColor(Color fill, ColorScheme scheme) {
  final lum = fill.computeLuminance();
  return lum > 0.45 ? scheme.onSurface : Colors.white;
}

bool noteMatchesTypeFilter(Note note, Set<String> types) =>
    types.isEmpty || types.contains(note.type);

final notesTypeFilterProvider = StateProvider<Set<String>>((ref) => {});

/// When false (default), done notes are hidden from the main list.
final showDoneNotesProvider = StateProvider<bool>((ref) => false);

/// True when the filters show everything: no type restriction and done
/// notes included (the "All" chip state).
bool notesFilterShowsAll(Set<String> types, bool showDone) =>
    types.isEmpty && showDone;

/// Android drawable resource basename per type (sync with res/drawable).
String noteTypeIconAssetName(String type) {
  switch (VesnaiTypePalette.bucket(normalizeNoteType(type))) {
    case 'Idea':
      return 'ic_note_type_idea';
    case 'Task':
      return 'ic_note_type_task';
    case 'Photo':
      return 'ic_note_type_photo';
    default:
      return 'ic_note_type_note';
  }
}

/// Filter chip with a type-colored icon (mint anchor + matched accents).
class NoteTypeFilterChip extends StatelessWidget {
  final String type;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const NoteTypeFilterChip({
    super.key,
    required this.type,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = noteTypeStyle(type, scheme);
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 16, color: style.color),
          const SizedBox(width: 6),
          Text(localizedNoteType(context, type)),
        ],
      ),
      selected: selected,
      onSelected: onSelected,
    );
  }
}
