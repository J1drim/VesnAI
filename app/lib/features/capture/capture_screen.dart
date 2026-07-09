import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api_client.dart';
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
  _PendingAttachment(this.name, this.bytes);
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
  bool _suggestingTags = false;
  String? _uploadStatus;
  StreamSubscription<SpeechResult>? _speechSub;
  bool _listening = false;
  _DictationTarget _dictationTarget = _DictationTarget.title;

  static const _imagePickOptions = (
    maxWidth: 1920.0,
    maxHeight: 1920.0,
    imageQuality: 85,
  );

  void _logCapture(String message) {
    if (kDebugMode) debugPrint('[capture] $message');
  }

  @override
  void initState() {
    super.initState();
    _titleFocusNode.addListener(_onTitleFocusChanged);
    _bodyEditorController.addListener(_onBodyEditorChanged);
  }

  @override
  void dispose() {
    _speechSub?.cancel();
    _bodyEditorController.removeListener(_onBodyEditorChanged);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).speechUnavailable),
        ));
      }
      return;
    }
    setState(() => _listening = true);
    _speechSub = speech.listen(localeId: _localeId()).listen(
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
    if (_tagsEditedByUser) return;
    final tagger = ref.read(taggerProvider);
    final s = tagger.suggest(_titleController.text, _bodyMarkdown);
    setState(() {
      _type = s.type;
      _tags = List<String>.from(s.tags);
    });
  }

  void _addTag(String raw) {
    final tag = raw.trim().toLowerCase().replaceAll('#', '');
    if (tag.isEmpty) return;
    setState(() {
      _tagsEditedByUser = true;
      if (!_tags.contains(tag)) _tags = [..._tags, tag];
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _tagsEditedByUser = true;
      _tags = _tags.where((t) => t != tag).toList();
    });
  }

  Future<void> _suggestTagsWithAi() async {
    final client = ref.read(apiClientProvider);
    if (client == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).tagSuggestionsNeedServer)),
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
          SnackBar(content: Text(AppLocalizations.of(context).couldNotSuggestTags('$e'))),
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
    _attachments.add(_PendingAttachment(x.name, await x.readAsBytes()));
    _applyPhotoTypeIfNeeded();
    setState(() {});
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    final file = result?.files.singleOrNull;
    if (file?.bytes == null) return;
    _attachments.add(_PendingAttachment(file!.name, file.bytes!));
    if (_isImage(file.name)) _applyPhotoTypeIfNeeded();
    setState(() {});
  }

  Future<void> _draw() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const DrawScreen()),
    );
    if (bytes == null) return;
    _attachments.add(_PendingAttachment('sketch-${DateTime.now().millisecondsSinceEpoch}.png', bytes));
    _applyPhotoTypeIfNeeded();
    setState(() {});
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _uploadStatus = null;
    });
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var synced = true;
    var saveFailed = false;
    final started = DateTime.now();
    try {
      final hasAttachments = _attachments.isNotEmpty;
      _logCapture(
        'save start attachments=${_attachments.length} '
        'bytes=${_attachments.map((a) => a.bytes.length).join(",")}',
      );
      var note = await ref.read(notesProvider.notifier).capture(
            title: _titleController.text.trim(),
            body: _bodyMarkdown.trim(),
            type: _type,
            tags: _tags,
            deferSync: hasAttachments,
          );

      if (hasAttachments) {
        final client = ref.read(apiClientProvider);
        final cache = ref.read(attachmentCacheProvider);
        if (client != null) {
          final buffer = StringBuffer(note.body);
          final rels = <String>[];
          var uploadFailures = 0;
          for (var i = 0; i < _attachments.length; i++) {
            final a = _attachments[i];
            if (mounted) {
              setState(() =>
                  _uploadStatus = l.uploadingPhoto(i + 1, _attachments.length));
            }
            try {
              final uniqueName =
                  '${DateTime.now().millisecondsSinceEpoch}-${a.name}';
              final uploadStarted = DateTime.now();
              final rel = await client.uploadAttachment(note.path, uniqueName, a.bytes);
              _logCapture(
                'upload ok ${a.name} ${a.bytes.length}B '
                '${DateTime.now().difference(uploadStarted).inMilliseconds}ms → $rel',
              );
              await cache.write(rel, a.bytes);
              rels.add(rel);
              buffer.write('\n\n![${a.name}]($rel)');
            } catch (e) {
              uploadFailures++;
              _logCapture('upload failed ${a.name}: $e');
              if (mounted) {
                messenger.showSnackBar(SnackBar(
                  content: Text(noteAttachmentUploadErrorMessage(
                      e, a.name, AppLocalizations.of(context))),
                ));
              }
            }
          }
          if (rels.isNotEmpty) {
            note = note.copyWith(
              body: buffer.toString(),
              attachments: rels,
              type: _type,
            );
            // Local save + background flush; the note is queued if offline.
            await ref.read(notesProvider.notifier).updateNote(note);
          } else if (uploadFailures > 0) {
            synced = false;
          }
        } else {
          messenger.showSnackBar(
              SnackBar(content: Text(l.attachmentsNeedServer)));
        }
      }
      if (!synced && mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(l.savedLocallyShort),
        ));
      }
      _logCapture(
        'save done path=${note.path} synced=$synced '
        '${DateTime.now().difference(started).inMilliseconds}ms',
      );
    } catch (e, st) {
      saveFailed = true;
      _logCapture('save failed: $e\n$st');
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(l.couldNotSaveNote('$e')),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadStatus = null;
        });
      }
    }
    if (!saveFailed && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.capture),
        actions: [
          IconButton(
            key: const Key('save-note'),
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
                  key: const Key('body-field'),
                  controller: _bodyEditorController,
                  initialMarkdown: '',
                  onMarkdownChanged: (_) => _recomputeTags(),
                  framed: false,
                ),
              ),
            ),
            if (_uploadStatus != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  _uploadStatus!,
                  style: Theme.of(context).textTheme.bodySmall,
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
                                onRemove: () =>
                                    setState(() => _attachments.removeAt(i)),
                              )
                            : Chip(
                                label: Text(_attachments[i].name),
                                onDeleted: () =>
                                    setState(() => _attachments.removeAt(i)),
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
                onTypeChanged: (v) => setState(() {
                  _type = v;
                  _typeManuallyEdited = true;
                  _tagsEditedByUser = true;
                }),
                onAddTag: _addTag,
                onRemoveTag: _removeTag,
                onSuggestTags: ref.watch(apiClientProvider) == null ||
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
                color: _listening ? Theme.of(context).colorScheme.error : null,
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                onPressed: _busy ? null : _toggleListen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
