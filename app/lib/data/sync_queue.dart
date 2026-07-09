import 'package:okf_dart/okf_dart.dart';

import '../models/note.dart';
import 'api_client.dart';
import 'local_store.dart';

/// Offline-first sync engine.
///
/// All edits land in the [LocalNoteStore] immediately and are marked pending.
/// When the server is reachable, [flush] pushes pending changes and pulls
/// server deltas. Connectivity is abstracted via [reachable] so tests can drive
/// online/offline transitions deterministically.
class SyncEngine {
  final LocalNoteStore store;
  final VesnaiApiClient? Function() clientProvider;
  final bool Function() reachable;
  int cursor = 0;

  static const _failureCooldown = Duration(seconds: 30);
  DateTime? _lastFailureAt;

  SyncEngine({
    required this.store,
    required this.clientProvider,
    required this.reachable,
    this.cursor = 0,
  });

  /// Skip automatic flush retries for a short window after a failed attempt.
  void resetFailureCircuit() => _lastFailureAt = null;

  Future<void> saveLocal(Note note) async {
    final existing = await store.get(note.path);
    final state = existing == null ? SyncState.pendingCreate : SyncState.pendingUpdate;
    await store.put(note.copyWith(syncState: state));
  }

  Future<void> deleteLocal(String path) async {
    final existing = await store.get(path);
    if (existing == null) return;
    await store.put(existing.copyWith(syncState: SyncState.pendingDelete));
  }

  /// Backfill the full note catalog from the server, then run a normal [flush].
  ///
  /// Incremental [flush] only pulls server deltas since [cursor], so notes that
  /// already existed on the server before this device started syncing (e.g.
  /// AI-generated notes) may never enter the delta. Listing the catalog and
  /// upserting it as `synced` makes those notes appear. Local pending edits are
  /// preserved. Returns the [flush] result (pushed count, or -1 if offline).
  Future<int> bootstrap({String device = 'app'}) async {
    if (!reachable()) return -1;
    final client = clientProvider();
    if (client == null) return -1;

    resetFailureCircuit();
    try {
      final remote = await client.listNotes();
      for (final note in remote) {
        final existing = await store.get(note.path);
        if (existing != null && existing.isPending) continue;
        var merged = note;
        // Defensive: never regress version when the catalog API omits it.
        if (existing != null &&
            !existing.isPending &&
            existing.version > merged.version) {
          merged = merged.copyWith(
            version: existing.version,
            updated: existing.updated.isNotEmpty ? existing.updated : merged.updated,
          );
        }
        await store.put(merged.copyWith(syncState: SyncState.synced));
      }
      return await flush(device: device, force: true);
    } catch (_) {
      _lastFailureAt = DateTime.now();
      return -1;
    }
  }

  /// Returns the number of pending changes successfully pushed, or -1 if the
  /// server was unreachable (changes stay queued).
  ///
  /// When [force] is false, skips the network attempt for
  /// [_failureCooldown] after a recent failure (background captures).
  Future<int> flush({String device = 'app', bool force = false}) async {
    if (!reachable()) return -1;
    final client = clientProvider();
    if (client == null) return -1;

    if (!force &&
        _lastFailureAt != null &&
        DateTime.now().difference(_lastFailureAt!) < _failureCooldown) {
      return -1;
    }

    try {
      final pending = await store.pending();
      final changes = <Map<String, dynamic>>[];
      for (final note in pending) {
        if (note.syncState == SyncState.pendingDelete) {
          changes.add({'path': note.path, 'deleted': true, 'doc': null});
        } else {
          changes.add({
            'path': note.path,
            'deleted': false,
            'doc': dumpConcept(note.toConcept()),
          });
        }
      }

      if (changes.isNotEmpty) {
        await client.push(changes, device: device);
        for (final note in pending) {
          if (note.syncState == SyncState.pendingDelete) {
            await store.remove(note.path);
          } else {
            await store.put(note.copyWith(syncState: SyncState.synced));
          }
        }
      }

      // Pull server deltas (enrichment, other devices) into the mirror.
      cursor = await store.getCursor();
      final delta = await client.pull(cursor);
      cursor = delta['cursor'] as int;
      await store.setCursor(cursor);
      for (final change in (delta['changes'] as List)) {
        final map = change as Map<String, dynamic>;
        final path = map['path'] as String;
        if (map['deleted'] == true) {
          await store.remove(path);
        } else if (map['doc'] != null) {
          final concept = parseConcept(map['doc'] as String);
          await store.put(Note.fromConcept(path, concept));
        }
      }
      _lastFailureAt = null;
      return changes.length;
    } catch (_) {
      _lastFailureAt = DateTime.now();
      return -1;
    }
  }
}
