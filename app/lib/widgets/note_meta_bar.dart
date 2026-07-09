import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/notes/note_type_ui.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

/// Compact single-row metadata bar for note editing: a type chip, the current
/// tag chips, and an add-tag chip. Type selection and tag entry open bottom
/// sheets so the writing surface stays uncluttered.
class NoteMetaBar extends ConsumerWidget {
  const NoteMetaBar({
    super.key,
    required this.type,
    required this.tags,
    required this.onTypeChanged,
    required this.onAddTag,
    required this.onRemoveTag,
    this.onSuggestTags,
    this.suggesting = false,
    this.enabled = true,
  });

  final String type;
  final List<String> tags;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onAddTag;
  final ValueChanged<String> onRemoveTag;

  /// AI tag suggestion; the button is hidden when null.
  final VoidCallback? onSuggestTags;
  final bool suggesting;
  final bool enabled;

  Future<void> _pickType(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                AppLocalizations.of(sheetContext).noteTypeSheetTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final t in kUserNoteTypes)
              ListTile(
                key: Key('type-option-$t'),
                leading: Icon(
                  noteTypeStyle(t, scheme).icon,
                  color: noteTypeStyle(t, scheme).color,
                ),
                title: Text(localizedNoteType(sheetContext, t)),
                trailing: t == type ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, t),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != type) onTypeChanged(picked);
  }

  Future<void> _addTagSheet(BuildContext context, Set<String> known) async {
    final result = await showModalBottomSheet<_TagSheetResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final l = AppLocalizations.of(sheetContext);
        final controller = TextEditingController();
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              final query = controller.text.trim().toLowerCase();
              final options = known
                  .where((t) => !tags.contains(t))
                  .where((t) => query.isEmpty || t.contains(query))
                  .take(12)
                  .toList()
                ..sort();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.addTag,
                            style:
                                Theme.of(sheetContext).textTheme.titleMedium,
                          ),
                        ),
                        if (onSuggestTags != null)
                          TextButton.icon(
                            key: const Key('suggest-tags-sheet'),
                            onPressed: () => Navigator.pop(
                              sheetContext,
                              const _TagSheetResult.suggest(),
                            ),
                            icon: const Icon(Icons.auto_awesome, size: 16),
                            label: Text(l.suggestTags),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('tag-sheet-field'),
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: l.addTag,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setSheetState(() {}),
                      onSubmitted: (v) => Navigator.pop(
                        sheetContext,
                        _TagSheetResult.tag(v),
                      ),
                    ),
                    if (options.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in options)
                            ActionChip(
                              key: Key('tag-option-$t'),
                              label: Text('#$t'),
                              onPressed: () => Navigator.pop(
                                sheetContext,
                                _TagSheetResult.tag(t),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (result == null) return;
    if (result.suggest) {
      onSuggestTags?.call();
    } else if (result.value.trim().isNotEmpty) {
      onAddTag(result.value);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final style = noteTypeStyle(type, scheme);
    final known = ref.watch(knownTagsProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ActionChip(
            key: const Key('meta-type-chip'),
            avatar: Icon(style.icon, size: 16, color: style.color),
            label: Text(localizedNoteType(context, type)),
            onPressed: enabled ? () => _pickType(context) : null,
          ),
          const SizedBox(width: 6),
          for (final tag in tags) ...[
            InputChip(
              key: Key('tag-$tag'),
              label: Text('#$tag'),
              onDeleted: enabled ? () => onRemoveTag(tag) : null,
            ),
            const SizedBox(width: 6),
          ],
          if (suggesting) ...[
            const Chip(
              avatar: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              label: SizedBox.shrink(),
            ),
            const SizedBox(width: 6),
          ],
          ActionChip(
            key: const Key('add-tag-chip'),
            avatar: const Icon(Icons.add, size: 16),
            label: Text(l.addTag),
            onPressed: enabled ? () => _addTagSheet(context, known) : null,
          ),
        ],
      ),
    );
  }
}

class _TagSheetResult {
  final String value;
  final bool suggest;
  const _TagSheetResult.tag(this.value) : suggest = false;
  const _TagSheetResult.suggest()
      : value = '',
        suggest = true;
}
