import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/attachment_cache.dart';
import '../../data/chat_attachment.dart';
import '../../data/chat_attachment_cache.dart';
import '../../l10n/app_localizations.dart';
import '../../models/note.dart';
import '../../providers.dart';
import '../../widgets/authenticated_image.dart';
import '../../widgets/chat_attachment_image.dart';
import '../../widgets/editor_bottom_bar.dart';
import '../../widgets/note_body_editor.dart';
import '../../widgets/note_markdown_view.dart';
import '../../widgets/note_meta_bar.dart';
import '../notes/delete_note_dialog.dart';
import '../notes/note_preview.dart';
import '../notes/note_type_ui.dart';

/// View + edit a single note. The body renders as Markdown (with inline,
/// authenticated attachment images) by default; the pencil toggles WYSIWYG editing.
/// Edits are saved offline-first (queued for sync).
class NoteDetailScreen extends ConsumerStatefulWidget {
  final String path;
  const NoteDetailScreen({super.key, required this.path});

  @override
  ConsumerState<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<NoteDetailScreen> {
  final _titleController = TextEditingController();
  final _bodyEditorController = NoteBodyEditorController();
  Note? _note;
  String? _hydratedUpdated;
  bool _busy = false;
  bool _editing = false;
  String _type = 'Note';
  List<String> _tags = const [];

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _syncFromNote(Note note) {
    final version = note.updated;
    if (_hydratedUpdated == version && _note?.path == note.path) {
      _note = note;
      return;
    }
    _note = note;
    _hydratedUpdated = version;
    _type = kUserNoteTypes.contains(note.type) ? note.type : 'Note';
    if (!_editing) {
      _titleController.text = note.title;
      _tags = List.of(note.tags);
    }
  }

  Future<void> _save() async {
    final base = _note;
    if (base == null) return;
    setState(() => _busy = true);
    final tags = List<String>.of(_tags);
    final updated = base.copyWith(
      title: _titleController.text.trim(),
      body: _bodyEditorController.markdown.trim(),
      tags: tags,
      type: _type,
    );
    await ref.read(notesProvider.notifier).updateNote(updated);
    final client = ref.read(apiClientProvider);
    if (client != null) {
      unawaited(client.recordTagFeedback(
        text: '${updated.title} ${updated.body}',
        tags: tags,
        action: 'accepted',
      ));
    }
    if (mounted) {
      setState(() {
        _note = updated;
        _hydratedUpdated = updated.updated;
        _busy = false;
        _editing = false;
      });
    }
  }

  Future<void> _delete() async {
    final note = _note ?? ref.read(noteByPathProvider(widget.path));
    final ok = await confirmDeleteNote(context, note: note);
    if (!ok || !mounted) return;
    await ref.read(notesProvider.notifier).delete(widget.path);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _enrich() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(notesProvider.notifier).enrich(widget.path, kind: 'idea');
      messenger.showSnackBar(SnackBar(content: Text(l.enrichRequested)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.enrichFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Toggle the "done" status. Done notes stay readable by the assistant but
  /// leave the review queue. Optimistic: the UI flips immediately, the local
  /// save + background server flush follow (offline-first).
  Future<void> _toggleDone() async {
    final base = _note ?? ref.read(noteByPathProvider(widget.path));
    if (base == null || _busy) return;
    final target = !base.done;
    final updated = base.copyWith(
      done: target,
      doneAt: target ? DateTime.now().toUtc().toIso8601String() : '',
    );
    final l = AppLocalizations.of(context);
    setState(() => _note = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(target ? l.markedDone : l.noteReopened)),
    );
    await ref.read(notesProvider.notifier).updateNote(updated);
    if (mounted) {
      final fresh = ref.read(noteByPathProvider(widget.path));
      if (fresh != null) {
        setState(() {
          _note = fresh;
          _hydratedUpdated = fresh.updated;
        });
      }
    }
  }

  Future<void> _toggleTaskBody(String newBody) async {
    final base = _note ?? ref.read(noteByPathProvider(widget.path));
    if (base == null || _busy) return;
    final updated = base.copyWith(body: newBody);
    setState(() => _note = updated);
    await ref.read(notesProvider.notifier).updateNote(updated);
    if (mounted) {
      final fresh = ref.read(noteByPathProvider(widget.path));
      if (fresh != null) {
        setState(() {
          _note = fresh;
          _hydratedUpdated = fresh.updated;
        });
      }
    }
  }

  /// Marena critique notes that reference this note as their source.
  List<Note> _critiquesOfThisNote() {
    final notes = ref.read(notesProvider).valueOrNull ?? const <Note>[];
    return [
      for (final n in notes)
        if (n.type == kCritiqueNoteType && n.source == widget.path) n,
    ];
  }

  /// The relative attachment path of the auto-generated image for this note, if
  /// a linked `GeneratedImage` child has synced in.
  String? _generatedImageRel() {
    final notes = ref.read(notesProvider).valueOrNull ?? const <Note>[];
    for (final n in notes) {
      if (n.type == 'GeneratedImage' && n.source == widget.path) {
        final m = RegExp(r'attachments/[^)\s]+').firstMatch(n.body);
        if (m != null) return m.group(0);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final notesAsync = ref.watch(notesProvider);
    final paired = ref.watch(serverConnectionProvider).isPaired;
    ref.watch(notesProvider); // re-render when a generated image syncs in
    final client = ref.watch(apiClientProvider);
    final cache = ref.watch(attachmentCacheProvider);
    final chatCache = ref.watch(chatAttachmentCacheProvider);
    final current = _note ?? ref.watch(noteByPathProvider(widget.path));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.noteScreenTitle),
        actions: [
          IconButton(
            key: const Key('toggle-edit'),
            tooltip: _editing ? l.view : l.edit,
            icon: Icon(_editing ? Icons.visibility_outlined : Icons.edit_outlined),
            onPressed: _busy ? null : () => setState(() => _editing = !_editing),
          ),
          if (current != null)
            IconButton(
              key: const Key('toggle-done'),
              tooltip: current.done ? l.reopen : l.markDone,
              icon: Icon(current.done
                  ? Icons.check_circle
                  : Icons.check_circle_outline),
              onPressed: _busy ? null : _toggleDone,
            ),
          if (paired)
            IconButton(
              key: const Key('enrich-note'),
              tooltip: l.enrichWithAi,
              icon: const Icon(Icons.auto_awesome),
              onPressed: _busy ? null : _enrich,
            ),
          IconButton(
            key: const Key('delete-note'),
            tooltip: l.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : _delete,
          ),
          if (_editing)
            IconButton(
              key: const Key('save-edit'),
              tooltip: l.save,
              icon: const Icon(Icons.check),
              onPressed: _busy ? null : _save,
            ),
        ],
      ),
      body: SafeArea(
        child: notesAsync.when(
          loading: () {
            final note = ref.watch(noteByPathProvider(widget.path));
            if (note == null) {
              return const Center(child: CircularProgressIndicator());
            }
            _syncFromNote(note);
            final display = _note ?? note;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: _editing
                  ? _buildEditor(display)
                  : _buildView(display, client, cache, chatCache),
            );
          },
          error: (e, _) => Center(child: Text(l.errorWithDetail('$e'))),
          data: (_) {
            final note = ref.watch(noteByPathProvider(widget.path));
            if (note == null) {
              return Center(child: Text(l.noteNotFound));
            }
            _syncFromNote(note);
            final display = _note ?? note;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: _editing
                  ? _buildEditor(display)
                  : _buildView(display, client, cache, chatCache),
            );
          },
        ),
      ),
    );
  }

  Widget _buildView(
    Note note,
    VesnaiApiClient? client,
    AttachmentCache cache,
    ChatAttachmentCache chatCache,
  ) {
    final l = AppLocalizations.of(context);
    final imageRel = _generatedImageRel();
    final isCritique = note.type == kCritiqueNoteType;
    final critiqueStyle = noteTypeStyle(kCritiqueNoteType, Theme.of(context).colorScheme);
    final critiques = _critiquesOfThisNote();
    return ListView(
      children: [
        if (isCritique)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Chip(
              avatar: Icon(critiqueStyle.icon, size: 16, color: critiqueStyle.color),
              label: Text(l.critiqueByMarena),
              backgroundColor: critiqueStyle.fill.withValues(alpha: 0.3),
              side: BorderSide(color: critiqueStyle.color),
            ),
          )
        else if (note.isGenerated)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Chip(
              avatar: const Icon(Icons.auto_awesome, size: 16),
              label: Text(l.aiGenerated),
            ),
          ),
        if (note.done)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Chip(
              avatar: const Icon(Icons.check_circle, size: 16),
              label: Text(l.done),
            ),
          ),
        Text(note.title.isEmpty ? l.untitled : note.title,
            style: Theme.of(context).textTheme.headlineSmall),
        if (note.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              spacing: 6,
              children: [for (final t in note.tags) Chip(label: Text('#$t'))],
            ),
          ),
        const SizedBox(height: 8),
        NoteMarkdownView(
          markdown: note.body,
          enabled: !_busy,
          onTaskToggle: _toggleTaskBody,
          sizedImageBuilder: (config) => _AttachmentImage(
            uri: config.uri,
            alt: config.alt,
            client: client,
            cache: cache,
            chatCache: chatCache,
          ),
        ),
        ..._extraAttachments(note, client, cache),
        if (isCritique && note.source.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(l.critiquedNote, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          _NoteLinkTile(
            key: const Key('critiqued-note-link'),
            path: note.source,
            onOpen: (path) => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => NoteDetailScreen(path: path)),
            ),
          ),
        ],
        if (critiques.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(critiqueStyle.icon, size: 18, color: critiqueStyle.color),
              const SizedBox(width: 8),
              Text(l.critiques, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          for (final c in critiques)
            Card(
              key: ValueKey('critique-${c.path}'),
              color: critiqueStyle.fill.withValues(alpha: 0.15),
              child: ListTile(
                leading: Icon(critiqueStyle.icon, color: critiqueStyle.color),
                title: Text(c.title.isEmpty ? l.typeCritique : c.title),
                subtitle: Text(
                  notePreviewBody(c),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteDetailScreen(path: c.path),
                  ),
                ),
              ),
            ),
        ],
        if (imageRel != null) ...[
          const SizedBox(height: 16),
          Text(l.generatedMemoryAid,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AuthenticatedImage(
              relPath: imageRel,
              cache: cache,
              client: client,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEditor(Note note) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note.isGenerated)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Chip(
              avatar: const Icon(Icons.auto_awesome, size: 16),
              label: Text(l.aiGenerated),
            ),
          ),
        TextField(
          key: const Key('edit-title'),
          controller: _titleController,
          style: Theme.of(context).textTheme.headlineSmall,
          decoration: InputDecoration(
            hintText: l.titleLabel,
            border: InputBorder.none,
            isDense: true,
          ),
        ),
        Expanded(
          child: NoteBodyEditor(
            key: const Key('edit-body'),
            controller: _bodyEditorController,
            initialMarkdown: note.body,
            hint: l.bodyHint,
            framed: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: NoteMetaBar(
            type: _type,
            tags: _tags,
            enabled: !_busy,
            onTypeChanged: (v) => setState(() => _type = v),
            onAddTag: (raw) {
              final tag = raw.trim().toLowerCase().replaceAll('#', '');
              if (tag.isEmpty) return;
              setState(() {
                if (!_tags.contains(tag)) _tags = [..._tags, tag];
              });
            },
            onRemoveTag: (tag) => setState(() {
              _tags = _tags.where((t) => t != tag).toList();
            }),
          ),
        ),
        EditorBottomBar(controller: _bodyEditorController),
      ],
    );
  }

  List<Widget> _extraAttachments(
      Note note, VesnaiApiClient? client, AttachmentCache cache) {
    if (note.attachments.isEmpty) return const [];
    final inBody = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');
    final linked = inBody
        .allMatches(note.body)
        .map((m) => m.group(1)!)
        .toSet();
    final extra = note.attachments.where((a) => !linked.contains(a)).toList();
    if (extra.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Text(AppLocalizations.of(context).attachments,
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      for (final rel in extra)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AuthenticatedImage(
            relPath: rel,
            cache: cache,
            client: client,
          ),
        ),
    ];
  }
}

/// Tappable link to another note by bundle path (shows its title when the
/// note is in the local mirror).
class _NoteLinkTile extends ConsumerWidget {
  final String path;
  final void Function(String path) onOpen;
  const _NoteLinkTile({super.key, required this.path, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(noteByPathProvider(path));
    return Card(
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(
          target == null || target.title.isEmpty ? path : target.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => onOpen(path),
      ),
    );
  }
}

/// Renders an in-note image. Rewrites relative `attachments/...` links to the
/// authenticated `GET /v1/attachments/...` endpoint; falls back to alt text.
class _AttachmentImage extends StatelessWidget {
  final Uri uri;
  final String? alt;
  final VesnaiApiClient? client;
  final AttachmentCache cache;
  final ChatAttachmentCache chatCache;
  const _AttachmentImage({
    required this.uri,
    this.alt,
    this.client,
    required this.cache,
    required this.chatCache,
  });

  @override
  Widget build(BuildContext context) {
    final raw = uri.toString();
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Image.network(raw,
          errorBuilder: (context, error, stack) => _fallback(context));
    }
    if (raw.startsWith('chat:')) {
      final rest = raw.substring(5);
      final slash = rest.indexOf('/');
      if (slash > 0) {
        final sessionId = rest.substring(0, slash);
        final filename = rest.substring(slash + 1);
        return ChatAttachmentImage(
          sessionId: sessionId,
          attachment: ChatAttachmentMeta(
            path: filename,
            kind: 'generated',
            filename: filename,
            sessionId: sessionId,
          ),
          client: client,
          cache: chatCache,
        );
      }
      return _fallback(context);
    }
    final idx = raw.indexOf('attachments/');
    if (idx == -1) return _fallback(context);
    final rel = raw.substring(idx);
    return AuthenticatedImage(
      relPath: rel,
      cache: cache,
      client: client,
      error: _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.broken_image_outlined, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text(alt?.isNotEmpty == true ? alt! : 'image')),
          ],
        ),
      );
}
