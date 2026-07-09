import 'dart:async';

import '../models/note.dart';
import 'local_store.dart';
import 'sync_queue.dart';
import 'tagging.dart';

/// Called after a background sync attempt completes ([synced] is true on success).
typedef FlushCompleteCallback = void Function(bool synced);

/// Coordinates local capture, on-device tagging and sync.
class NoteRepository {
  final LocalNoteStore store;
  final SyncEngine sync;
  final Tagger tagger;
  final FlushCompleteCallback? onFlushComplete;

  NoteRepository({
    required this.store,
    required this.sync,
    required this.tagger,
    this.onFlushComplete,
  });

  Future<List<Note>> notes() => store.all();

  /// Capture a new note. On-device tagging proposes a type + tags (user can
  /// override). Saved locally first (offline-first), then queued for sync.
  Future<Note> capture({
    required String title,
    required String body,
    String? type,
    List<String>? tags,
    bool deferSync = false,
  }) async {
    final suggestion = tagger.suggest(title, body);
    final now = DateTime.now().toUtc().toIso8601String();
    final slug = _slug(title);
    final note = Note(
      path: 'notes/$slug-${now.hashCode.toUnsigned(32).toRadixString(16)}.md',
      title: title,
      body: body,
      type: type ?? suggestion.type,
      tags: tags ?? suggestion.tags,
      updated: now,
      syncState: SyncState.pendingCreate,
    );
    await sync.saveLocal(note);
    if (!deferSync) _flushInBackground();
    return note;
  }

  /// Apply an edit to an existing note. Saved locally first (queued as a
  /// pending update), then flushed to the server in the background so callers
  /// never block on network I/O.
  Future<void> update(Note note) async {
    final existing = await store.get(note.path);
    final now = DateTime.now().toUtc().toIso8601String();
    final baseVersion = existing != null
        ? (existing.version > note.version ? existing.version : note.version)
        : note.version;
    final version = existing != null ? baseVersion + 1 : note.version;
    await sync.saveLocal(note.copyWith(updated: now, version: version));
    _flushInBackground();
  }

  Future<void> delete(String path) async {
    await sync.deleteLocal(path);
    _flushInBackground();
  }

  void _flushInBackground() {
    unawaited(() async {
      final synced = await tryFlush();
      onFlushComplete?.call(synced);
    }());
  }

  /// Push pending changes when online; returns false if the server was unreachable.
  Future<bool> tryFlush() async {
    try {
      final result = await sync
          .flush()
          .timeout(const Duration(seconds: 5), onTimeout: () => -1);
      return result >= 0;
    } catch (_) {
      return false;
    }
  }

  Future<int> refresh() => sync.flush();

  /// Pull the full server catalog into the local mirror, then flush pending
  /// changes. See [SyncEngine.bootstrap].
  Future<int> bootstrap() => sync.bootstrap();

  static String _slug(String text) {
    final s = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return s.isEmpty ? 'note' : (s.length > 60 ? s.substring(0, 60) : s);
  }
}
