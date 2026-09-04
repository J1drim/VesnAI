import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:okf_dart/okf_dart.dart';

import '../../data/attachment_cache.dart';
import '../../l10n/app_localizations.dart';
import '../../models/note.dart';
import '../../providers.dart';

/// Server recovery is shared across devices; local snapshots also protect notes
/// that were deleted before their first successful upload.
class RecoveryScreen extends ConsumerStatefulWidget {
  final String? path;
  const RecoveryScreen({super.key, this.path});
  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<Map<String, dynamic>>> _local() async =>
      (jsonDecode(
                await ref.read(localStoreProvider).localValue('local_trash') ??
                    '[]',
              )
              as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

  Future<void> _load() async {
    final items = <Map<String, dynamic>>[];
    String? error;
    try {
      if (widget.path == null)
        items.addAll((await _local()).map((i) => {...i, 'local': true}));
      final client = ref.read(apiClientProvider);
      if (client == null) throw StateError('offline');
      final result = await client.libraryRecovery(
        widget.path == null ? 'trash' : 'history',
        query: widget.path == null ? {} : {'path': widget.path!},
      );
      if (result['available'] == false) throw StateError('history unavailable');
      items.addAll(
        (result[widget.path == null ? 'items' : 'revisions'] as List).map(
          (i) => (i as Map).cast<String, dynamic>(),
        ),
      );
    } catch (_) {
      if (mounted) error = AppLocalizations.of(context).recoveryUnavailable;
    }
    if (mounted)
      setState(() {
        _items = items;
        _error = error;
        _busy = false;
      });
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(child: SelectableText(body)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(title),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _removeLocal(String id) async {
    final store = ref.read(localStoreProvider);
    await store.transaction(() async {
      final items = await _local();
      items.removeWhere((i) => i['id'] == id);
      await store.setLocalValue('local_trash', jsonEncode(items));
    });
  }

  Future<void> _restoreLocal(Map<String, dynamic> item) async {
    final drafts = ref.read(captureDraftStoreProvider);
    final old = Note.fromConcept(
      item['path'] as String,
      parseConcept(item['doc'] as String),
    );
    var body = old.body;
    final paths = <String>[];
    for (final path in AttachmentCache.pathsFromNote(old)) {
      final bytes = await ref.read(attachmentCacheProvider).readBytes(path);
      if (bytes == null)
        throw StateError('Local attachment unavailable: $path');
      final replacement = await drafts.persistAttachment(
        path.split('/').last,
        bytes,
      );
      paths.add(replacement);
      body = body.replaceAll(path, replacement);
    }
    await drafts.enqueueAttachments(paths);
    final restoredPath = 'notes/restored-${item['id']}.md';
    if (await ref.read(localStoreProvider).get(restoredPath) == null) {
      final metadata = {...old.frontmatter};
      metadata['vesnai'] = {...?(metadata['vesnai'] as Map?)}..remove('id');
      await ref
          .read(notesProvider.notifier)
          .updateNote(
            old.copyWith(
              path: restoredPath,
              body: body,
              attachments: paths,
              version: 1,
              baseVersion: 0,
              frontmatter: metadata,
            ),
          );
    }
    await _removeLocal(item['id'] as String);
  }

  Future<void> _act(Map<String, dynamic> item, {bool discard = false}) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final client = ref.read(apiClientProvider);
      if (widget.path != null) {
        if (client == null) throw StateError('offline');
        final revision = item['revision'] as String;
        final response = await client.libraryRecovery(
          'revision',
          query: {'path': widget.path!, 'revision': revision},
        );
        final old = Note.fromConcept(
          widget.path!,
          parseConcept(response['doc'] as String),
        );
        if (!mounted ||
            !await _confirm(l.restoreRevision, '${old.title}\n\n${old.body}'))
          return;
        final current = await ref.read(localStoreProvider).get(widget.path!);
        if (current == null || current.isPending)
          throw StateError(l.syncBeforeRestore);
        await client.libraryRecovery(
          'history/restore',
          method: 'POST',
          body: {
            'path': widget.path,
            'revision': revision,
            'base_version': current.version,
          },
        );
        await ref.read(notesProvider.notifier).sync();
      } else {
        final local = item['local'] == true;
        final text = discard
            ? l.discardTrashConfirm
            : local
            ? l.restoreLocalCopyConfirm
            : l.restoreTrashConfirm;
        if (!await _confirm(
          discard ? l.discardDraft : l.restoreNote,
          '${item['title']}\n\n$text',
        ))
          return;
        if (local) {
          if (discard) {
            final old = Note.fromConcept(
              item['path'] as String,
              parseConcept(item['doc'] as String),
            );
            await _removeLocal(item['id'] as String);
            await ref
                .read(captureDraftStoreProvider)
                .releaseUnused(AttachmentCache.pathsFromNote(old));
          } else {
            await _restoreLocal(item);
          }
        } else {
          if (client == null) throw StateError('offline');
          await client.libraryRecovery(
            'trash/${item['id']}${discard ? '' : '/restore'}',
            method: discard ? 'DELETE' : 'POST',
          );
          await ref.read(notesProvider.notifier).sync();
        }
      }
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.restoreFailed('$error'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.path == null ? l.trash : l.noteHistory),
        actions: [
          IconButton(
            tooltip: l.retry,
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.path == null ? l.trashRetention : l.historyExplanation,
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
                  title: Text(item['title'] as String? ?? ''),
                  subtitle: Text(
                    '${item['deleted_at'] ?? item['date']}\n${item['local'] == true ? l.thisDevice : l.pairedServer}',
                  ),
                  onTap: _busy ? null : () => _act(item),
                  trailing: widget.path == null
                      ? IconButton(
                          tooltip: l.discardDraft,
                          onPressed: _busy
                              ? null
                              : () => _act(item, discard: true),
                          icon: const Icon(Icons.delete_forever_outlined),
                        )
                      : const Icon(Icons.history),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
