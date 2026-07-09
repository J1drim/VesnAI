import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'note_body_editor.dart';

/// Slim keyboard-adjacent toolbar for note editing screens.
///
/// A single row with an "Aa" toggle that reveals the rich-text formatting
/// toolbar above the bar (progressive disclosure), optional screen-specific
/// [actions] (e.g. camera / attach / draw), and an optional [trailing] widget
/// (e.g. the dictation mic). While [listening], the action icons are replaced
/// by a compact mic status so no extra status row is needed.
class EditorBottomBar extends StatefulWidget {
  const EditorBottomBar({
    super.key,
    required this.controller,
    this.actions = const [],
    this.trailing,
    this.listening = false,
  });

  final NoteBodyEditorController controller;
  final List<Widget> actions;
  final Widget? trailing;
  final bool listening;

  @override
  State<EditorBottomBar> createState() => _EditorBottomBarState();
}

class _EditorBottomBarState extends State<EditorBottomBar> {
  bool _showFormatting = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final quill = widget.controller.quill;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              alignment: Alignment.topCenter,
              child: _showFormatting && quill != null
                  ? NoteFormattingToolbar(controller: quill)
                  : const SizedBox(width: double.infinity),
            ),
            Row(
              children: [
                IconButton(
                  key: const Key('format-toggle'),
                  tooltip: l.formatting,
                  isSelected: _showFormatting,
                  icon: const Icon(Icons.text_format),
                  onPressed: quill == null
                      ? null
                      : () =>
                          setState(() => _showFormatting = !_showFormatting),
                ),
                if (widget.listening)
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.mic, size: 16, color: scheme.error),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            l.listening,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  ...widget.actions,
                  const Spacer(),
                ],
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ],
        );
      },
    );
  }
}
