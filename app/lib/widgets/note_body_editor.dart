import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../utils/note_markdown_codec.dart';
import 'note_attachment_image.dart';

/// External handle for reading markdown from a [NoteBodyEditor].
class NoteBodyEditorController extends ChangeNotifier {
  _NoteBodyEditorState? _state;
  QuillController? _quill;

  String get markdown => _state?.currentMarkdown ?? '';

  /// The underlying Quill controller, available once [NoteBodyEditor] mounts.
  QuillController? get quill => _quill;

  /// Whether the body editor currently has keyboard focus. Listeners are
  /// notified on focus changes.
  bool get bodyHasFocus => _state?._focusNode.hasFocus ?? false;

  /// Replaces the editor content with [markdown].
  void setMarkdown(String markdown) => _state?._loadMarkdown(markdown);

  void _attach(_NoteBodyEditorState state, QuillController quill) {
    _state = state;
    _quill = quill;
    notifyListeners();
  }

  void _notifyFocusChanged() => notifyListeners();

  void _detach(_NoteBodyEditorState state) {
    if (_state != state) return;
    _state = null;
    _quill = null;
    notifyListeners();
  }
}

/// Formatting toolbar for [NoteBodyEditor]. Shown contextually by the
/// editor bottom bar (progressive disclosure via the "Aa" toggle).
class NoteFormattingToolbar extends StatelessWidget {
  const NoteFormattingToolbar({super.key, required this.controller});

  final QuillController controller;

  static const toolbarHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.outlineVariant),
            bottom: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: QuillSimpleToolbar(
          controller: controller,
          config: const QuillSimpleToolbarConfig(
            multiRowsDisplay: false,
            showFontFamily: false,
            showFontSize: false,
            showUnderLineButton: false,
            showColorButton: false,
            showBackgroundColorButton: false,
            showClearFormat: false,
            showAlignmentButtons: false,
            showIndent: false,
            showLink: false,
            showSearchButton: false,
            showSubscript: false,
            showSuperscript: false,
            showSmallButton: false,
            showLineHeightButton: false,
            showCodeBlock: false,
            showUndo: true,
            showRedo: true,
            showBoldButton: true,
            showItalicButton: true,
            showStrikeThrough: true,
            showInlineCode: true,
            showHeaderStyle: true,
            headerStyleType: HeaderStyleType.buttons,
            showListNumbers: true,
            showListBullets: true,
            showListCheck: true,
            showQuote: true,
          ),
        ),
      ),
    );
  }
}

class _NoteImageEmbedBuilder extends EmbedBuilder {
  const _NoteImageEmbedBuilder(this.imageBuilder);

  final Widget Function(String src) imageBuilder;

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final data = embedContext.node.value.data;
    final src = data?.toString() ?? '';
    if (src.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Icon(Icons.image_outlined, size: 18),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: imageBuilder(src),
    );
  }
}

class _UnknownEmbedBuilder extends EmbedBuilder {
  const _UnknownEmbedBuilder();

  @override
  String get key => 'unknown';

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final type = embedContext.node.value.type;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '[$type embed]',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  @override
  String toPlainText(Embed node) => '[${node.value.type}]';
}

/// WYSIWYG note body field. Pair with an `EditorBottomBar` for contextual
/// formatting controls.
class NoteBodyEditor extends ConsumerStatefulWidget {
  const NoteBodyEditor({
    super.key,
    this.controller,
    required this.initialMarkdown,
    this.onMarkdownChanged,
    this.fieldKey,
    this.hint,
    this.readOnly = false,
    this.framed = true,
  });

  final NoteBodyEditorController? controller;
  final String initialMarkdown;
  final ValueChanged<String>? onMarkdownChanged;
  final Key? fieldKey;

  /// Placeholder text; defaults to the localized "What do you want to
  /// remember?" prompt.
  final String? hint;
  final bool readOnly;

  /// When false, the editor renders flat (no border box) for a
  /// document-style writing surface.
  final bool framed;

  @override
  ConsumerState<NoteBodyEditor> createState() => _NoteBodyEditorState();
}

class _NoteBodyEditorState extends ConsumerState<NoteBodyEditor> {
  static final _codec = NoteMarkdownCodec();

  late QuillController _quillController;
  late FocusNode _focusNode;
  late ScrollController _scrollController;
  bool _suppressNotify = false;

  String get currentMarkdown => _codec.documentToMarkdown(_quillController.document);

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _scrollController = ScrollController();
    _quillController = QuillController(
      document: _codec.markdownToDocument(widget.initialMarkdown),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _quillController.readOnly = widget.readOnly;
    _quillController.addListener(_onDocumentChanged);
    widget.controller?._attach(this, _quillController);
  }

  @override
  void didUpdateWidget(covariant NoteBodyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this, _quillController);
    }
    if (oldWidget.initialMarkdown != widget.initialMarkdown &&
        widget.initialMarkdown != currentMarkdown &&
        !_focusNode.hasFocus) {
      _loadMarkdown(widget.initialMarkdown);
    }
    if (oldWidget.readOnly != widget.readOnly) {
      _quillController.readOnly = widget.readOnly;
    }
  }

  void _loadMarkdown(String markdown) {
    _suppressNotify = true;
    widget.controller?._detach(this);
    _quillController.removeListener(_onDocumentChanged);
    _quillController.dispose();
    _quillController = QuillController(
      document: _codec.markdownToDocument(markdown),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _quillController.readOnly = widget.readOnly;
    _quillController.addListener(_onDocumentChanged);
    widget.controller?._attach(this, _quillController);
    _suppressNotify = false;
    setState(() {});
  }

  void _onDocumentChanged() {
    if (_suppressNotify) return;
    widget.onMarkdownChanged?.call(currentMarkdown);
  }

  void _onFocusChanged() {
    widget.controller?._notifyFocusChanged();
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _quillController.removeListener(_onDocumentChanged);
    _quillController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(apiClientProvider);
    final cache = ref.watch(attachmentCacheProvider);
    final chatCache = ref.watch(chatAttachmentCacheProvider);

    final editor = QuillEditor.basic(
      key: widget.fieldKey,
      controller: _quillController,
      focusNode: _focusNode,
      scrollController: _scrollController,
      config: QuillEditorConfig(
        placeholder:
            widget.hint ?? AppLocalizations.of(context).bodyEditorHint,
        padding: EdgeInsets.zero,
        expands: true,
        scrollable: true,
        embedBuilders: [
          _NoteImageEmbedBuilder(
            (src) => NoteAttachmentImage(
              uri: src,
              client: client,
              cache: cache,
              chatCache: chatCache,
            ),
          ),
        ],
        unknownEmbedBuilder: const _UnknownEmbedBuilder(),
      ),
    );

    if (!widget.framed) return editor;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: editor,
      ),
    );
  }
}
