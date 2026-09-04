import 'dart:async';

import 'package:okf_dart/okf_dart.dart';

import '../models/note.dart';
import 'api_client.dart';
import 'local_store.dart';

/// Local edits are durable before network work. Network operations are serialized;
/// acknowledgements only clear the exact revision that was submitted.
class SyncEngine {
  final LocalNoteStore store;
  final VesnaiApiClient? Function() clientProvider;
  final bool Function() reachable;
  int cursor;
  Future<void> _network = Future.value();
  static const _failureCooldown = Duration(seconds: 30);
  DateTime? _lastFailureAt;

  SyncEngine({
    required this.store,
    required this.clientProvider,
    required this.reachable,
    this.cursor = 0,
  });

  void resetFailureCircuit() => _lastFailureAt = null;

  Future<int> _serialize(Future<int> Function() action) {
    final result = _network.then((_) => action());
    _network = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> saveLocal(Note note) => store.transaction(() async {
    final existing = await store.get(note.path);
    final creating =
        existing == null || existing.syncState == SyncState.pendingCreate;
    final base = existing?.baseVersion ?? -1;
    await store.put(
      note.copyWith(
        syncState: existing?.syncState == SyncState.conflict
            ? SyncState.conflict
            : creating
            ? SyncState.pendingCreate
            : SyncState.pendingUpdate,
        baseVersion: creating
            ? 0
            : base >= 0
            ? base
            : existing.version,
        frontmatter: {...?existing?.frontmatter, ...note.frontmatter},
        syncError: existing?.syncError ?? '',
        serverDoc: existing?.serverDoc ?? '',
        serverVersion: existing?.serverVersion ?? 0,
        conflictDeleted: false,
      ),
    );
  });

  Future<void> deleteLocal(String path) => store.transaction(() async {
    final note = await store.get(path);
    if (note == null) return;
    // Keep even an unsynced create as a tombstone: it may currently be uploading.
    await store.put(
      note.copyWith(
        baseVersion: note.baseVersion >= 0 ? note.baseVersion : note.version,
        syncState: SyncState.pendingDelete,
        syncError: '',
      ),
    );
  });

  Future<int> bootstrap({String device = 'app'}) => _serialize(() async {
    if (!reachable()) return -1;
    final client = clientProvider();
    if (client == null) return -1;
    resetFailureCircuit();
    try {
      final remote = await client.listNotes();
      await store.transaction(() async {
        for (final note in remote) {
          final existing = await store.get(note.path);
          if (existing != null &&
              (existing.isPending || existing.version > note.version))
            continue;
          await store.put(note.copyWith(syncState: SyncState.synced));
        }
      });
      return await _flush(device: device, force: true);
    } catch (_) {
      _lastFailureAt = DateTime.now();
      return -1;
    }
  });

  Future<int> flush({String device = 'app', bool force = false}) =>
      _serialize(() => _flush(device: device, force: force));

  Future<int> _flush({required String device, required bool force}) async {
    if (!reachable()) return -1;
    final client = clientProvider();
    if (client == null) return -1;
    if (!force &&
        _lastFailureAt != null &&
        DateTime.now().difference(_lastFailureAt!) < _failureCooldown)
      return -1;
    try {
      final pending = (await store.pending())
          .where((n) => n.syncState != SyncState.conflict)
          .toList();
      final changes = <Map<String, dynamic>>[
        for (final note in pending)
          {
            'path': note.path,
            'deleted': note.syncState == SyncState.pendingDelete,
            'doc': note.syncState == SyncState.pendingDelete
                ? null
                : dumpConcept(note.toConcept()),
            if (note.baseVersion >= 0) 'base_version': note.baseVersion,
          },
      ];
      var pushed = 0;
      if (changes.isNotEmpty) {
        final response = await client.push(changes, device: device);
        final applied = (response['applied'] as List? ?? [])
            .cast<String>()
            .toSet();
        final conflicts = <String, Map>{
          for (final c in (response['conflicts'] as List? ?? []))
            (c as Map)['path'] as String: c,
        };
        final versions = response['versions'] as Map? ?? {};
        await store.transaction(() async {
          for (final submitted in pending) {
            final current = await store.get(submitted.path);
            if (current == null) continue;
            final conflict = conflicts[submitted.path];
            if (conflict != null) {
              await store.put(
                current.copyWith(
                  syncState: SyncState.conflict,
                  syncError: conflict['error']?.toString() ?? 'concurrent edit',
                  serverDoc: conflict['server_doc']?.toString() ?? '',
                  serverVersion: (conflict['server_version'] as int?) ?? 0,
                  conflictDeleted: current.syncState == SyncState.pendingDelete,
                ),
              );
            } else if (applied.contains(submitted.path)) {
              pushed++;
              final remoteVersion =
                  (versions[submitted.path] as int?) ?? submitted.version;
              if (_sameRevision(current, submitted)) {
                if (submitted.syncState == SyncState.pendingDelete) {
                  await store.remove(submitted.path);
                } else {
                  await store.put(
                    current.copyWith(
                      syncState: SyncState.synced,
                      version: remoteVersion,
                      baseVersion: remoteVersion,
                      syncError: '',
                    ),
                  );
                }
              } else {
                // A newer local edit remains pending, based on the accepted upload.
                await store.put(
                  current.copyWith(
                    baseVersion: remoteVersion,
                    syncState: current.syncState == SyncState.pendingDelete
                        ? SyncState.pendingDelete
                        : SyncState.pendingUpdate,
                  ),
                );
              }
            } else {
              await store.put(
                current.copyWith(
                  syncError: 'server did not acknowledge this change',
                ),
              );
            }
          }
        });
      }
      final delta = await client.pull(await store.getCursor());
      final nextCursor = delta['cursor'] as int;
      // Parse before touching the mirror, then commit the entire batch + cursor.
      final parsed = <({String path, Note? note})>[
        for (final raw in delta['changes'] as List)
          (
            path: raw['path'] as String,
            note: raw['deleted'] == true
                ? null
                : Note.fromConcept(
                    raw['path'] as String,
                    parseConcept(raw['doc'] as String),
                  ),
          ),
      ];
      await store.transaction(() async {
        for (final change in parsed) {
          final local = await store.get(change.path);
          if (local?.isPending == true) continue;
          if (change.note == null) {
            await store.remove(change.path);
          } else {
            await store.put(change.note!);
          }
        }
        await store.setCursor(nextCursor);
      });
      cursor = nextCursor;
      _lastFailureAt = null;
      return pushed;
    } catch (_) {
      _lastFailureAt = DateTime.now();
      return -1;
    }
  }

  /// Resolve against the latest server version; a subsequent race is detected
  /// by base_version on the next upload. No note is overwritten remotely here.
  Future<void> resolveConflict(String path, String resolution) =>
      _serialize(() async {
        if (!{'mine', 'server', 'both'}.contains(resolution))
          throw ArgumentError.value(resolution);
        final client = clientProvider();
        if (client == null || !reachable())
          throw StateError('server unavailable');
        final remote = (await client.listNotes())
            .where((n) => n.path == path)
            .firstOrNull;
        await store.transaction(() async {
          final local = await store.get(path);
          if (local == null) return;
          if (resolution == 'server' || resolution == 'both') {
            if (resolution == 'both') {
              final copyPath =
                  'notes/recovered-' +
                  DateTime.now().microsecondsSinceEpoch.toString() +
                  '.md';
              final metadata = {...local.frontmatter};
              metadata['vesnai'] = {...?(metadata['vesnai'] as Map?)}
                ..remove('id')
                ..remove('created');
              await store.put(
                local.copyWith(
                  path: copyPath,
                  frontmatter: metadata,
                  syncState: SyncState.pendingCreate,
                  baseVersion: 0,
                  version: 1,
                  syncError: '',
                  serverDoc: '',
                  serverVersion: 0,
                  conflictDeleted: false,
                ),
              );
            }
            if (remote == null) {
              await store.remove(path);
            } else {
              await store.put(remote);
            }
          } else {
            await store.put(
              local.copyWith(
                baseVersion: remote?.version ?? 0,
                version: (remote?.version ?? 0) + 1,
                syncState: local.conflictDeleted
                    ? SyncState.pendingDelete
                    : remote == null
                    ? SyncState.pendingCreate
                    : SyncState.pendingUpdate,
                syncError: '',
                serverDoc: '',
                serverVersion: 0,
                conflictDeleted: false,
              ),
            );
          }
        });
        resetFailureCircuit();
        return 0;
      }).then((_) {});

  static bool _sameRevision(Note a, Note b) =>
      a.syncState == b.syncState &&
      a.version == b.version &&
      a.updated == b.updated &&
      dumpConcept(a.toConcept()) == dumpConcept(b.toConcept());
}
