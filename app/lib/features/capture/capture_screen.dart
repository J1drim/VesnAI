import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/capture_draft.dart';
import '../../data/speech_input.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../widgets/editor_bottom_bar.dart';
import '../../widgets/note_body_editor.dart';
import '../../widgets/note_meta_bar.dart';
import 'draw_screen.dart';

/// Quick capture: text/idea plus optional photo/file/drawing attachments.
/// On-device tagging proposes a type + tags which the user can edit.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _PendingAttachment {
  final String name;
  final Uint8List bytes;
  final String path;
  _PendingAttachment(this.name, this.bytes, this.path);
}

const _imageExts = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'};

bool _isImage(String name) {
  final lower = name.toLowerCase();
  return _imageExts.any(lower.endsWith);
}

/// A small image thumbnail with a remove button, shown for pending photo/sketch
/// attachments before they're uploaded.
class _ThumbPreview extends StatelessWidget {
  final Uint8List bytes;
  final String name;
  final VoidCallback onRemove;
  const _ThumbPreview({
    required this.bytes,
    required this.name,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, width: 72, height: 72, fit: BoxFit.cover),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: IconButton(
            tooltip: AppLocalizations.of(context).removeAttachment(name),
            iconSize: 18,
            icon: const Icon(Icons.cancel),
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }
}

enum _DictationTarget { title, body }

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _titleController = TextEditingController();
  final _titleFocusNode = FocusNode();
  final _bodyEditorController = NoteBodyEditorController();
  String _type = 'Note';
  List<String> _tags = const ['misc'];
  bool _tagsEditedByUser = false;
  bool _typeManuallyEdited = false;
  final List<_PendingAttachment> _attachments = [];
  bool _busy = false;
  bool _draftReady = false;
  bool _draftLoadError = false;
  bool _saved = false;
  String _draftPath =
      'notes/capture-${DateTime.now().microsecondsSinceEpoch}.md';
  String _source = '';
  String _draftBody = '';
  String _editorInitialBody = '';
  bool _suggestingTags = false;
  StreamSubscription<SpeechResult>? _speechSub;
  bool _listening = false;
  _DictationTarget _dictationTarget = _DictationTarget.title;

  static const _imagePickOptions = (
    maxWidth: 1920.0,
    maxHeight: 1920.0,
    imageQuality: 85,
  );

  @override
  void initState() {
    super.initState();
    _titleFocusNode.addListener(_onTitleFocusChanged);
    _bodyEditorController.addListener(_onBodyEditorChanged);
    _titleController.addListener(_queueDraftSave);
    unawaited(_restoreDraft());
  }

  CaptureDraftStore get _drafts => ref.read(captureDraftStoreProvider);

  Future<void> _restoreDraft() async {
    _draftLoadError = false;
    try {
      final draft = await _drafts.load();
      if (!mounted) return;
      if (draft != null) {
        _attachments.clear();
        _draftPath = draft['path'] as String;
        _titleController.text = draft['title'] as String? ?? '';
        _draftBody = draft['body'] as String? ?? '';
        _editorInitialBody = _draftBody;
        _type = draft['type'] as String? ?? 'Note';
        _tags = (draft['tags'] as List? ?? []).cast<String>();
        _source = draft['source'] as String? ?? '';
        _tagsEditedByUser = true;
        _typeManuallyEdited = true;
        for (final item in draft['attachments'] as List? ?? []) {
          final bytes = await ref
              .read(attachmentCacheProvider)
              .readBytes(item['path'] as String);
          if (bytes == null) throw StateError('Draft attachment is missing');
          _attachments.add(
            _PendingAttachment(
              item['name'] as String,
              bytes,
              item['path'] as String,
            ),
          );
        }
      }
    } catch (error) {
      _draftLoadError = true;
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).couldNotSaveNote('$error'),
            ),
          ),
        );
    }
    if (mounted) setState(() => _draftReady = true);
  }

  Map<String, dynamic> _draftSnapshot() => {
    'path': _draftPath,
    'title': _titleController.text,
    'body': _draftBody,
    'type': _type,
    'tags': [..._tags],
    'source': _source,
    'attachments': [
      for (final a in _attachments) {'name': a.name, 'path': a.path},
    ],
  };

  void _queueDraftSave() {
    if (!_draftReady || _saved || _draftLoadError) return;
    unawaited(
      _drafts.save(_draftSnapshot()).catchError((Object error) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).couldNotSaveNote('$error'),
              ),
            ),
          );
      }),
    );
  }

  Future<void> _addAttachment(String name, Uint8List bytes) async {
    final path = await _drafts.persistAttachment(name, bytes);
    if (!mounted) return;
    setState(() {
      if (!_attachments.any((a) => a.path == path))
        _attachments.add(_PendingAttachment(name, bytes, path));
      if (_isImage(name)) _applyPhotoTypeIfNeeded();
    });
    await _drafts.save(_draftSnapshot());
  }

  Future<void> _removeAttachment(int index) async {
    final path = _attachments[index].path;
    setState(() => _attachments.removeAt(index));
    await _drafts.save(_draftSnapshot());
    await _drafts.releaseUnused([path]);
  }

  Future<void> _discardDraft() async {
    final l = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.discardDraft),
        content: Text(l.discardDraftConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.discardDraft),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    try {
      _saved = true;
      await _drafts.clear();
      await _drafts.releaseUnused(_attachments.map((a) => a.path));
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        setState(() {
          _titleController.clear();
          _draftBody = '';
          _bodyEditorController.setMarkdown('');
          _attachments.clear();
          _saved = false;
          _draftLoadError = false;
        });
      }
    } catch (error) {
      _saved = false;
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.couldNotSaveNote('$error'))));
    }
  }

  @override
  void dispose() {
    _speechSub?.cancel();
    _bodyEditorController.removeListener(_onBodyEditorChanged);
    _titleController.removeListener(_queueDraftSave);
    _titleFocusNode.removeListener(_onTitleFocusChanged);
    _titleFocusNode.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _onTitleFocusChanged() {
    if (_titleFocusNode.hasFocus) _dictationTarget = _DictationTarget.title;
  }

  void _onBodyEditorChanged() {
    if (_bodyEditorController.bodyHasFocus) {
      _dictationTarget = _DictationTarget.body;
    }
  }

  String get _bodyMarkdown => _bodyEditorController.markdown;

  String _localeId() {
    final lang = Localizations.localeOf(context).languageCode;
    return lang == 'pl' ? 'pl_PL' : 'en_US';
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _stopListening();
      return;
    }
    final speech = ref.read(speechInputProvider);
    if (!await speech.initialize()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).speechUnavailable),
          ),
        );
      }
      return;
    }
    setState(() => _listening = true);
    _speechSub = speech
        .listen(localeId: _localeId())
        .listen(
          (result) {
            if (_dictationTarget == _DictationTarget.title) {
              _titleController.value = TextEditingValue(
                text: result.text,
                selection: TextSelection.collapsed(offset: result.text.length),
              );
            } else {
              _bodyEditorController.setMarkdown(result.text);
            }
            if (result.isFinal) {
              _stopListening();
              _recomputeTags();
            }
          },
          onError: (_) => _stopListening(),
          onDone: () {
            if (mounted && _listening) setState(() => _listening = false);
          },
        );
  }

  Future<void> _stopListening() async {
    await ref.read(speechInputProvider).stop();
    await _speechSub?.cancel();
    _speechSub = null;
    if (mounted) setState(() => _listening = false);
  }

  void _recomputeTags() {
    _draftBody = _bodyMarkdown;
    if (_tagsEditedByUser) {
      _queueDraftSave();
      return;
    }
    final tagger = ref.read(taggerProvider);
    final s = tagger.suggest(_titleController.text, _bodyMarkdown);
    setState(() {
      _type = s.type;
      _tags = List<String>.from(s.tags);
    });
    _queueDraftSave();
  }

  void _addTag(String raw) {
    final tag = raw.trim().toLowerCase().replaceAll('#', '');
    if (tag.isEmpty) return;
    setState(() {
      _tagsEditedByUser = true;
      if (!_tags.contains(tag)) _tags = [..._tags, tag];
    });
    _queueDraftSave();
  }

  void _removeTag(String tag) {
    setState(() {
      _tagsEditedByUser = true;
      _tags = _tags.where((t) => t != tag).toList();
    });
    _queueDraftSave();
  }

  Future<void> _suggestTagsWithAi() async {
    final client = ref.read(apiClientProvider);
    if (client == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).tagSuggestionsNeedServer,
            ),
          ),
        );
      }
      return;
    }
    setState(() => _suggestingTags = true);
    try {
      final result = await client.suggestTags(
        title: _titleController.text.trim(),
        body: _bodyMarkdown.trim(),
      );
      if (!mounted) return;
      setState(() {
        _type = result.type;
        _tags = List<String>.from(result.tags);
        _tagsEditedByUser = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).couldNotSuggestTags('$e'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _suggestingTags = false);
    }
  }

  void _applyPhotoTypeIfNeeded() {
    if (!_typeManuallyEdited) _type = 'Photo';
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: _imagePickOptions.maxWidth,
      maxHeight: _imagePickOptions.maxHeight,
      imageQuality: _imagePickOptions.imageQuality,
    );
    if (x == null) return;
    await _addAttachment(x.name, await x.readAsBytes());
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await _addAttachment(file.name, bytes);
  }

  Future<void> _draw() async {
    final bytes = await Navigator.of(
      context,
    ).push<Uint8List>(MaterialPageRoute(builder: (_) => const DrawScreen()));
    if (bytes == null) return;
    await _addAttachment(
      'sketch-${DateTime.now().millisecondsSinceEpoch}.png',
      bytes,
    );
  }

  Future<void> _save() async {
    if (_busy || !_draftReady) return;
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    try {
      _draftBody = _bodyMarkdown;
      await _drafts.save(_draftSnapshot());
      final paths = _attachments.map((a) => a.path).toList();
      await _drafts.enqueueAttachments(paths);
      final body = StringBuffer(_draftBody.trim());
      for (final a in _attachments) {
        final name = a.name.replaceAll(RegExp(r'[\[\]()]'), '_');
        body.write(
          '\n\n' +
              (_isImage(a.name) ? '!' : '') +
              '[' +
              name +
              '](' +
              a.path +
              ')',
        );
      }
      final existing = await ref.read(localStoreProvider).get(_draftPath);
      final identical =
          existing != null &&
          existing.title == _titleController.text.trim() &&
          existing.body == body.toString() &&
          existing.type == _type &&
          listEquals(existing.tags, _tags);
      if (!identical) {
        // A recovered draft must never replace a note changed after its save.
        if (existing != null) {
          _draftPath =
              'notes/recovered-' +
              DateTime.now().microsecondsSinceEpoch.toString() +
              '.md';
          await _drafts.save(_draftSnapshot());
        }
        await ref
            .read(notesProvider.notifier)
            .capture(
              path: _draftPath,
              title: _titleController.text.trim(),
              body: body.toString(),
              type: _type,
              tags: _tags,
              attachments: paths,
              source: _source,
            );
      }
      _saved = true;
      await _drafts.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.savedLocallyShort)));
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    } catch (error) {
      _saved = false;
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.couldNotSaveNote('$error'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!_draftReady || _draftLoadError) {
      return Scaffold(
        appBar: AppBar(title: Text(l.capture)),
        body: Center(
          child: !_draftReady
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.draftUnavailable),
                    TextButton(onPressed: _restoreDraft, child: Text(l.retry)),
                    TextButton(
                      onPressed: _discardDraft,
                      child: Text(l.discardDraft),
                    ),
                  ],
                ),
        ),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.capture),
          actions: [
            IconButton(
              tooltip: l.discardDraft,
              onPressed: _busy ? null : _discardDraft,
              icon: const Icon(Icons.delete_outline),
            ),
          PopupMenuButton<String>(
            enabled: !_busy,
              tooltip: l.templates,
              icon: const Icon(Icons.description_outlined),
              onSelected: (value) {
                final template = switch (value) {
                  'meeting' => l.meetingTemplate,
                  'idea' => l.ideaTemplate,
                  _ => l.readingTemplate,
                };
                _tagsEditedByUser = true;
                _typeManuallyEdited = true;
                setState(() {
                  if (_bodyMarkdown.trim().isEmpty)
                    _type = value == 'idea' ? 'Idea' : 'Note';
                  _draftBody = [
                    _bodyMarkdown.trim(),
                    template,
                  ].where((s) => s.isNotEmpty).join('\n\n');
                  _bodyEditorController.setMarkdown(_draftBody);
                });
                _queueDraftSave();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'meeting', child: Text(l.templateMeeting)),
                PopupMenuItem(value: 'idea', child: Text(l.templateIdea)),
                PopupMenuItem(value: 'reading', child: Text(l.templateReading)),
              ],
            ),
            IconButton(
              key: const Key('save-note'),
              tooltip: l.save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(
                enabled: !_busy,
                  key: const Key('title-field'),
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  style: Theme.of(context).textTheme.headlineSmall,
                  decoration: InputDecoration(
                    hintText: l.titleLabel,
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (_) => _recomputeTags(),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                child: NoteBodyEditor(
                  readOnly: _busy,
                    key: const Key('body-field'),
                    controller: _bodyEditorController,
                  initialMarkdown: _editorInitialBody,
                    onMarkdownChanged: (_) => _recomputeTags(),
                    framed: false,
                  ),
                ),
              ),
              if (_attachments.isNotEmpty)
                SizedBox(
                  height: 80,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    children: [
                      for (var i = 0; i < _attachments.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _isImage(_attachments[i].name)
                              ? _ThumbPreview(
                                  bytes: _attachments[i].bytes,
                                  name: _attachments[i].name,
                                  onRemove: () => _removeAttachment(i),
                                )
                              : Chip(
                                  label: Text(_attachments[i].name),
                                  onDeleted: () => _removeAttachment(i),
                                ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: NoteMetaBar(
                  type: _type,
                  tags: _tags,
                  enabled: !_busy,
                  suggesting: _suggestingTags,
                  onTypeChanged: (v) {
                    setState(() {
                      _type = v;
                      _typeManuallyEdited = true;
                      _tagsEditedByUser = true;
                    });
                    _queueDraftSave();
                  },
                  onAddTag: _addTag,
                  onRemoveTag: _removeTag,
                  onSuggestTags:
                      ref.watch(apiClientProvider) == null ||
                          _busy ||
                          _suggestingTags
                      ? null
                      : _suggestTagsWithAi,
                ),
              ),
              EditorBottomBar(
                controller: _bodyEditorController,
                listening: _listening,
                actions: [
                  IconButton(
                    tooltip: l.photo,
                    onPressed: _busy ? null : _pickPhoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                  ),
                  IconButton(
                    tooltip: l.attachFile,
                    onPressed: _busy ? null : _pickFile,
                    icon: const Icon(Icons.attach_file),
                  ),
                  IconButton(
                    tooltip: l.draw,
                    onPressed: _busy ? null : _draw,
                    icon: const Icon(Icons.draw_outlined),
                  ),
                ],
                trailing: IconButton(
                  key: const Key('capture-mic'),
                  tooltip: _listening ? l.stopDictation : l.speak,
                  color: _listening
                      ? Theme.of(context).colorScheme.error
                      : null,
                  icon: Icon(_listening ? Icons.stop : Icons.mic),
                  onPressed: _busy ? null : _toggleListen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
