import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../data/api_client.dart';
import '../data/chat_attachment.dart';
import '../features/note_detail/note_detail_screen.dart';
import '../l10n/app_localizations.dart';
import '../models/note.dart';
import '../providers.dart';
import 'media_viewer_screen.dart';

Future<void> openChatImageFullscreen(
  BuildContext context,
  Uint8List bytes, {
  String? title,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MediaViewerScreen(bytes: bytes, title: title),
    ),
  );
}

Future<void> shareChatImageBytes(Uint8List bytes, {String filename = 'image.png'}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(file.path)], text: filename);
}

Future<void> shareChatFileBytes(Uint8List bytes, {required String filename}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(file.path)], text: filename);
}

Future<void> openChatFileBytes(Uint8List bytes, {required String filename}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(file.path)], text: filename);
}

Future<void> showChatFileActions({
  required BuildContext context,
  required WidgetRef ref,
  required String sessionId,
  required ChatAttachmentMeta attachment,
  required Uint8List bytes,
  VesnaiApiClient? client,
}) async {
  final l = AppLocalizations.of(context);
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(l.openShare),
            onTap: () => Navigator.pop(ctx, 'open'),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(l.shareSave),
            onTap: () => Navigator.pop(ctx, 'share'),
          ),
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: Text(l.addToNotes),
            onTap: () => Navigator.pop(ctx, 'notes'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case 'open':
      await openChatFileBytes(bytes, filename: attachment.filename);
    case 'share':
      await shareChatFileBytes(bytes, filename: attachment.filename);
    case 'notes':
      if (client == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.connectToSaveToNotes)),
          );
        }
        return;
      }
      await _addChatImageToNotes(
        context: context,
        ref: ref,
        client: client,
        sessionId: sessionId,
        attachment: attachment,
      );
  }
}

Future<void> showChatImageActions({
  required BuildContext context,
  required WidgetRef ref,
  required String sessionId,
  required ChatAttachmentMeta attachment,
  required Uint8List bytes,
  VesnaiApiClient? client,
}) async {
  final l = AppLocalizations.of(context);
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.fullscreen),
            title: Text(l.fullscreen),
            onTap: () => Navigator.pop(ctx, 'fullscreen'),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(l.shareSave),
            onTap: () => Navigator.pop(ctx, 'share'),
          ),
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: Text(l.addToNotes),
            onTap: () => Navigator.pop(ctx, 'notes'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case 'fullscreen':
      await openChatImageFullscreen(context, bytes, title: attachment.filename);
    case 'share':
      await shareChatImageBytes(bytes, filename: attachment.filename);
    case 'notes':
      if (client == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.connectToSaveToNotes)),
          );
        }
        return;
      }
      await _addChatImageToNotes(
        context: context,
        ref: ref,
        client: client,
        sessionId: sessionId,
        attachment: attachment,
      );
  }
}

Future<void> _addChatImageToNotes({
  required BuildContext context,
  required WidgetRef ref,
  required VesnaiApiClient client,
  required String sessionId,
  required ChatAttachmentMeta attachment,
}) async {
  final l = AppLocalizations.of(context);
  final notes = ref.read(notesProvider).valueOrNull ?? const <Note>[];
  final choice = await showModalBottomSheet<_NoteSaveChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.45,
          minChildSize: 0.25,
          maxChildSize: 0.85,
          builder: (_, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l.addToNotes, style: Theme.of(ctx).textTheme.titleMedium),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(l.newNote),
                onTap: () => Navigator.pop(ctx, const _NoteSaveChoice.newNote()),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: notes.length,
                  itemBuilder: (_, i) {
                    final note = notes[i];
                    return ListTile(
                      title: Text(note.title.isEmpty ? l.untitled : note.title),
                      subtitle: Text(note.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(ctx, _NoteSaveChoice.existing(note.path)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (!context.mounted || choice == null) return;
  try {
    final result = await client.saveChatAttachmentToNote(
      sessionId,
      attachment.path,
      notePath: choice.notePath,
      title: attachment.filename,
    );
    await ref.read(notesProvider.notifier).sync();
    if (!context.mounted) return;
    final notePath = result['note_path'] as String? ?? choice.notePath ?? '';
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final openPath = notePath;
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.savedToNotes),
        duration: const Duration(seconds: 5),
        action: openPath.isNotEmpty
            ? SnackBarAction(
                label: l.open,
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  appNavigatorKey.currentState?.push(
                    MaterialPageRoute(
                      builder: (_) => NoteDetailScreen(path: openPath),
                    ),
                  );
                },
              )
            : null,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.couldNotSaveImageToNotes)),
      );
    }
  }
}

class _NoteSaveChoice {
  final String? notePath;
  const _NoteSaveChoice.newNote() : notePath = null;
  const _NoteSaveChoice.existing(this.notePath);
}
