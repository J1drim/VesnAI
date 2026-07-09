import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../utils/external_url.dart';
import '../utils/task_list_markdown.dart';

/// Renders note markdown with tappable task-list checkboxes.
class NoteMarkdownView extends StatefulWidget {
  const NoteMarkdownView({
    super.key,
    required this.markdown,
    required this.onTaskToggle,
    this.enabled = true,
    this.sizedImageBuilder,
  });

  final String markdown;
  final Future<void> Function(String newBody) onTaskToggle;
  final bool enabled;
  final MarkdownSizedImageBuilder? sizedImageBuilder;

  @override
  State<NoteMarkdownView> createState() => _NoteMarkdownViewState();
}

class _NoteMarkdownViewState extends State<NoteMarkdownView> {
  var _checkboxIndex = 0;
  var _busy = false;

  Future<void> _toggleAt(int index) async {
    if (!widget.enabled || _busy) return;
    final updated = toggleTaskListItem(widget.markdown, index);
    if (updated == widget.markdown) return;
    setState(() => _busy = true);
    try {
      await widget.onTaskToggle(updated);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _checkboxIndex = 0;
    final data = widget.markdown.isEmpty ? '_No content yet._' : widget.markdown;
    return MarkdownBody(
      data: data,
      sizedImageBuilder: widget.sizedImageBuilder,
      onTapLink: (text, href, title) {
        if (href != null && isExternalUrl(href)) {
          openExternalUrl(href, context: context);
        }
      },
      checkboxBuilder: (checked) {
        final index = _checkboxIndex++;
        return Checkbox(
          value: checked,
          onChanged: widget.enabled && !_busy
              ? (_) => _toggleAt(index)
              : null,
        );
      },
    );
  }
}
