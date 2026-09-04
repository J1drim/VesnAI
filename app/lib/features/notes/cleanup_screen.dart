import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:okf_dart/okf_dart.dart';

import '../../data/library_cleanup.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../note_detail/note_detail_screen.dart';

class CleanupScreen extends ConsumerStatefulWidget {
  const CleanupScreen({super.key});
  @override
  ConsumerState<CleanupScreen> createState() => _CleanupScreenState();
}

class _CleanupScreenState extends ConsumerState<CleanupScreen> {
  List<CleanupSuggestion> _items = [];
  bool _busy = false;
  bool _scanned = false;
  Future<void> _scan() async {
    setState(() => _busy = true);
    try {
      final notes = await ref.read(localStoreProvider).all();
      final items = inspectLibrary(notes);
      if (mounted)
        setState(() {
          _items = items;
          _scanned = true;
        });
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(CleanupSuggestion item) async {
    final l = AppLocalizations.of(context);
    if (item.kind == 'broken' && !item.editable) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => NoteDetailScreen(path: item.note.path),
        ),
      );
      if (mounted) await _scan();
      return;
    }
    final action = switch (item.kind) {
      'duplicate' => l.archive,
      'tag' => l.applyTagChange,
      _ => l.removeBrokenLink,
    };
    final other = item.kind == 'duplicate'
        ? await ref.read(localStoreProvider).get(item.value)
        : null;
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(
              '${item.note.title}\n\n${item.note.body}\n\n${other == null ? '${item.value} → ${item.replacement}' : '${l.duplicateContent}: ${other.title}\n${other.body}'}',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final current = await ref.read(localStoreProvider).get(item.note.path);
      if (current == null ||
          dumpConcept(current.toConcept()) !=
              dumpConcept(item.note.toConcept()))
        throw StateError(l.cleanupChanged);
      final stillValid =
          inspectLibrary(await ref.read(localStoreProvider).all()).any(
            (suggestion) =>
                suggestion.kind == item.kind &&
                suggestion.note.path == item.note.path &&
                suggestion.value == item.value &&
                suggestion.replacement == item.replacement,
          );
      if (!stillValid) throw StateError(l.cleanupChanged);
      final updated = switch (item.kind) {
        'duplicate' => current.copyWith(archived: true),
        'tag' => current.copyWith(
          tags: current.tags
              .map((t) => t == item.value ? item.replacement : t)
              .toSet()
              .toList(),
        ),
        _ => current.copyWith(
          links: current.links.where((link) => link != item.value).toList(),
        ),
      };
      await ref.read(notesProvider.notifier).updateNote(updated);
      if (mounted) await _scan();
    } catch (error) {
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
    return Scaffold(
      appBar: AppBar(title: Text(l.libraryCleanup)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l.cleanupExplanation),
          ),
          FilledButton(
            onPressed: _busy ? null : _scan,
            child: Text(l.scanLibrary),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_scanned && _items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.noCleanupSuggestions),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
                  title: Text(item.note.title),
                  subtitle: Text(switch (item.kind) {
                    'duplicate' => '${l.duplicateContent}: ${item.value}',
                    'tag' =>
                      '${l.inconsistentTag}: ${item.value} → ${item.replacement}',
                    _ => '${l.brokenLink}: ${item.value}',
                  }),
                  trailing: Icon(
                    item.editable
                        ? Icons.preview_outlined
                        : Icons.edit_outlined,
                  ),
                  onTap: _busy ? null : () => _review(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
