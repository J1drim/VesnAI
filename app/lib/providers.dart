import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:http/http.dart' as http;

import 'data/api_client.dart';
import 'data/app_preferences.dart';
import 'data/attachment_cache.dart';
import 'data/chat_attachment_cache.dart';
import 'data/chat_location_service.dart';
import 'data/chat_store.dart';
import 'data/drift/database.dart';
import 'data/connection_store.dart';
import 'data/graph_layout_store.dart';
import 'data/local_store.dart';
import 'data/location_context.dart';
import 'data/notification_service.dart';
import 'data/repository.dart';
import 'data/server_discovery.dart';
import 'data/shared_storage.dart';
import 'data/speech_input.dart';
import 'data/sync_queue.dart';
import 'data/tagging.dart';
import 'data/voice_cache.dart';
import 'features/notes/note_preview.dart';
import 'l10n/l10n_outside_widgets.dart';
import 'models/note.dart';

/// Holds the paired-server connection (null until the device is paired).
class ServerConnection {
  final Uri? baseUrl;
  final String? token;
  final String? deviceId;
  const ServerConnection({this.baseUrl, this.token, this.deviceId});
  bool get isPaired => baseUrl != null && token != null;
}

/// Durable credential store. Overridden in [main] with a [SecureConnectionStore]
/// and in tests with an [InMemoryConnectionStore].
final connectionStoreProvider =
    Provider<ConnectionStore>((ref) => SecureConnectionStore());

/// Owns the live [ServerConnection] and persists it via [ConnectionStore].
class ConnectionController extends Notifier<ServerConnection> {
  @override
  ServerConnection build() => const ServerConnection();

  /// Load any previously-saved connection from secure storage on startup.
  Future<void> hydrate() async {
    final saved = await ref.read(connectionStoreProvider).load();
    if (saved != null) {
      state = ServerConnection(
        baseUrl: Uri.parse(saved.baseUrl),
        token: saved.token,
        deviceId: saved.deviceId,
      );
    }
  }

  /// Pair this device, persist the token, and update the live connection.
  Future<void> pair({
    required Uri baseUrl,
    required String code,
    required String deviceName,
  }) async {
    final result = await pairWithServer(
      baseUrl,
      code,
      deviceName,
      client: ref.read(httpClientProvider),
    );
    await ref.read(connectionStoreProvider).save(
          baseUrl: baseUrl.toString(),
          token: result.token,
          deviceId: result.deviceId,
        );
    state = ServerConnection(
      baseUrl: baseUrl,
      token: result.token,
      deviceId: result.deviceId,
    );
    // Backfill the full server catalog (including AI-generated notes that
    // predate this device) now that we're paired. Best effort: pairing has
    // already succeeded, and the catalog also backfills on the next sync.
    try {
      await ref.read(notesProvider.notifier).bootstrap();
    } catch (_) {
      // Ignore; notes will appear on the next manual sync.
    }
  }

  /// Revoke this device on the server (best effort) and clear local credentials.
  Future<void> unpair() async {
    final client = ref.read(apiClientProvider);
    if (client != null && state.deviceId != null) {
      try {
        await client.revokeDevice(state.deviceId!);
      } catch (_) {
        // Server may be unreachable; clearing local creds is still correct.
      }
    }
    await ref.read(connectionStoreProvider).clear();
    state = const ServerConnection();
  }
}

final serverConnectionProvider =
    NotifierProvider<ConnectionController, ServerConnection>(ConnectionController.new);

final appPreferencesStoreProvider =
    Provider<AppPreferencesStore>((ref) => SecureAppPreferencesStore());

/// Persists force-directed graph node positions. Overridden in [main] on device;
/// defaults to in-memory for tests.
final graphLayoutStoreProvider = Provider<GraphLayoutStore>(
  (ref) => InMemoryGraphLayoutStore(),
);

class AppLocaleController extends Notifier<AppLocale> {
  @override
  AppLocale build() => AppLocale.system;

  Future<void> hydrate() async {
    state = await ref.read(appPreferencesStoreProvider).appLocale();
  }

  Future<void> set(AppLocale value) async {
    await ref.read(appPreferencesStoreProvider).setAppLocale(value);
    state = value;
  }
}

/// UI locale of the app (system default, English or Polish).
final appLocaleProvider = NotifierProvider<AppLocaleController, AppLocale>(
  AppLocaleController.new,
);

class AssistantLanguageController extends Notifier<AssistantLanguage> {
  @override
  AssistantLanguage build() => AssistantLanguage.auto;

  Future<void> hydrate() async {
    state = await ref.read(appPreferencesStoreProvider).assistantLanguage();
  }

  Future<void> set(AssistantLanguage value) async {
    await ref.read(appPreferencesStoreProvider).setAssistantLanguage(value);
    state = value;
  }
}

final assistantLanguageProvider =
    NotifierProvider<AssistantLanguageController, AssistantLanguage>(
  AssistantLanguageController.new,
);

final readRepliesAloudProvider = FutureProvider<bool>((ref) async {
  return ref.read(appPreferencesStoreProvider).readRepliesAloud();
});

class ShareLocationWithChatController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> hydrate() async {
    state = await ref.read(appPreferencesStoreProvider).shareLocationWithChat();
  }

  Future<void> set(bool value) async {
    await ref.read(appPreferencesStoreProvider).setShareLocationWithChat(value);
    state = value;
    if (value) {
      final saved = ref.read(savedChatLocationProvider);
      final resolved = await ref.read(chatLocationServiceProvider).resolveForChat(
            shareEnabled: true,
            saved: saved,
          );
      if (resolved != null) {
        await ref.read(savedChatLocationProvider.notifier).save(resolved);
      }
    }
  }
}

final shareLocationWithChatProvider =
    NotifierProvider<ShareLocationWithChatController, bool>(
  ShareLocationWithChatController.new,
);

class SavedChatLocationController extends Notifier<SavedLocation?> {
  @override
  SavedLocation? build() => null;

  Future<void> hydrate() async {
    final raw = await ref.read(appPreferencesStoreProvider).savedChatLocationJson();
    state = SavedLocation.fromJsonString(raw);
  }

  Future<void> save(SavedLocation? location) async {
    await ref
        .read(appPreferencesStoreProvider)
        .setSavedChatLocationJson(location?.toJsonString());
    state = location;
  }
}

final savedChatLocationProvider =
    NotifierProvider<SavedChatLocationController, SavedLocation?>(
  SavedChatLocationController.new,
);

final chatLocationServiceProvider =
    Provider<ChatLocationService>((ref) => ChatLocationService());

/// Whether first-run onboarding has been completed (hydrated in [main]).
final onboardedProvider = StateProvider<bool>((ref) => false);

/// Mark onboarding complete (persist + update state).
Future<void> completeOnboarding(WidgetRef ref) async {
  await ref.read(connectionStoreProvider).setOnboarded();
  ref.read(onboardedProvider.notifier).state = true;
}

/// LAN discovery of `_vesnai._tcp` servers.
final serverDiscoveryProvider =
    Provider<ServerDiscovery>((ref) => NsdServerDiscovery());

final discoveredServersProvider = StreamProvider<List<DiscoveredServer>>(
  (ref) => ref.watch(serverDiscoveryProvider).watch(),
);

/// Single shared Drift database for notes + chat (one SQLite connection).
final vesnaiDatabaseProvider = Provider<VesnaiDatabase>((ref) {
  final db = VesnaiDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final chatStoreProvider = Provider<ChatStore>((ref) {
  return ChatStore(ref.watch(vesnaiDatabaseProvider));
});

/// In-memory by default (tests/previews). [main] overrides this with a
/// [DriftNoteStore] for durable on-device persistence.
final localStoreProvider = Provider<LocalNoteStore>((ref) => InMemoryNoteStore());

final taggerProvider = Provider<Tagger>((ref) => const HeuristicTagger());

/// On-device speech-to-text for the chat mic. Overridden in widget tests with
/// a fake so the mic flow can be driven without a platform plugin.
final speechInputProvider =
    Provider<SpeechInputService>((ref) => NativeSpeechInputService());

/// Shared HTTP client. Overridden in [main] with [createPlatformHttpClient].
/// Widget tests use a plain [http.Client] via the default implementation.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final apiClientProvider = Provider<VesnaiApiClient?>((ref) {
  final conn = ref.watch(serverConnectionProvider);
  if (!conn.isPaired) return null;
  return VesnaiApiClient(
    baseUrl: conn.baseUrl!,
    token: conn.token!,
    client: ref.watch(httpClientProvider),
  );
});

/// On-disk cache for note attachment images. Initialized in [main].
final attachmentCacheProvider = Provider<AttachmentCache>((ref) {
  throw StateError('attachmentCacheProvider must be initialized in main()');
});

final chatAttachmentCacheProvider = Provider<ChatAttachmentCache>((ref) {
  throw StateError('chatAttachmentCacheProvider must be initialized in main()');
});

/// On-disk cache for chat TTS audio replay. Initialized in [main].
final voiceCacheProvider = Provider<VoiceCache>((ref) {
  throw StateError('voiceCacheProvider must be initialized in main()');
});

/// Server-reported settings (offline mode, models, languages, secret names).
final serverSettingsProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return client.settings();
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    store: ref.watch(localStoreProvider),
    clientProvider: () => ref.read(apiClientProvider),
    reachable: () => ref.read(apiClientProvider) != null,
  );
});

final repositoryProvider = Provider<NoteRepository>((ref) {
  return NoteRepository(
    store: ref.watch(localStoreProvider),
    sync: ref.watch(syncEngineProvider),
    tagger: ref.watch(taggerProvider),
    onFlushComplete: (synced) {
      if (synced) unawaited(ref.read(notesProvider.notifier).reload());
    },
  );
});

/// Bridge to native home-screen widgets. In-memory by default (tests/previews);
/// [main] overrides with [PlatformSharedWidgetStorage] on device.
final sharedWidgetStorageProvider =
    Provider<SharedWidgetStorage>((ref) => InMemorySharedWidgetStorage());

/// OS notifications for completed background jobs. No-op by default; [main]
/// overrides with [LocalNotifier] on device.
final notifierProvider = Provider<JobNotifier>((ref) => const NoopNotifier());

/// Notes list state with explicit refresh after captures.
final notesProvider = AsyncNotifierProvider<NotesNotifier, List<Note>>(
  NotesNotifier.new,
);

/// Distinct tags from the local note mirror (for capture autocomplete).
final knownTagsProvider = Provider<Set<String>>((ref) {
  final notes = ref.watch(notesProvider).valueOrNull ?? const [];
  return {for (final n in notes) ...n.tags};
});

/// Timestamp of the last successful sync (null until first sync).
final lastSyncedProvider = StateProvider<DateTime?>((ref) => null);

/// Load a single note from the in-memory list. Updates when [notesProvider] reloads.
final noteByPathProvider = Provider.family<Note?, String>((ref, path) {
  final notes = ref.watch(notesProvider).valueOrNull;
  if (notes == null) return null;
  for (final n in notes) {
    if (n.path == path) return n;
  }
  return null;
});

class NotesNotifier extends AsyncNotifier<List<Note>> {
  Future<void>? _syncInFlight;
  String? _lastPublishedEncoded;

  @override
  Future<List<Note>> build() async {
    final result = await AsyncValue.guard(() async {
      final notes = await ref.read(repositoryProvider).notes();
      await _publishWidgetSnapshot(notes);
      return notes;
    });
    return result.when(
      data: (d) => d,
      error: (e, _) => throw e,
      loading: () => throw StateError('unreachable'),
    );
  }

  Future<void> reload({int retries = 1}) async {
    state = const AsyncLoading<List<Note>>().copyWithPrevious(state);
    for (var attempt = 0; attempt <= retries; attempt++) {
      state = await AsyncValue.guard(() async {
        final notes = await ref.read(repositoryProvider).notes();
        await _publishWidgetSnapshot(notes);
        return notes;
      });
      if (!state.hasError || attempt == retries) break;
      final err = state.error.toString();
      if (!err.contains('database is locked') && !err.contains('SqliteException(5)')) {
        break;
      }
      await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
    }
  }

  /// Mirror the most recent notes into the shared store the home-screen
  /// widgets read. Preserves existing chat recents when [chats] is omitted.
  Future<void> _publishWidgetSnapshot(List<Note> notes, {List<WidgetChat>? chats}) async {
    final storage = ref.read(sharedWidgetStorageProvider);
    final chatRecents = chats ??
        (await storage.readSnapshot())?.chatRecents ??
        const <WidgetChat>[];
    final recents = notes
        .where(noteVisibleInMainList)
        .take(kWidgetRecentsLimit)
        .map((n) => WidgetNote(
              title: n.title.isEmpty ? '(untitled)' : n.title,
              type: n.type,
              generated: n.isGenerated,
              path: n.path,
            ))
        .toList();
    final encoded = WidgetSnapshot(recents, chatRecents: chatRecents).encode();
    if (encoded == _lastPublishedEncoded) return;
    _lastPublishedEncoded = encoded;
    await storage.writeSnapshot(WidgetSnapshot.decode(encoded));
  }

  /// Update only the chat portion of the widget snapshot (keeps current notes).
  Future<void> publishChatRecents(List<WidgetChat> chats) async {
    final notes = state.valueOrNull ?? await ref.read(repositoryProvider).notes();
    await _publishWidgetSnapshot(notes, chats: chats);
  }

  /// Publish notes + optional chats to the home-screen widget.
  Future<void> publishWidgetSnapshot({List<WidgetChat>? chats}) async {
    final notes = await ref.read(repositoryProvider).notes();
    await _publishWidgetSnapshot(notes, chats: chats);
  }

  /// Publish notes and chat sessions from local Drift (no server required).
  Future<void> publishFullWidgetSnapshot() async {
    final notes = await ref.read(repositoryProvider).notes();
    final stored = await ref.read(chatStoreProvider).sessions();
    final chats = stored
        .take(kWidgetRecentsLimit)
        .map((s) => WidgetChat(id: s.id, title: s.title, updated: s.updated))
        .toList();
    await _publishWidgetSnapshot(notes, chats: chats);
  }

  /// Ingest quick captures made from a home-screen widget while the app was
  /// closed. Called on launch/foreground.
  Future<void> ingestQuickCaptures() async {
    final captures = await ref.read(sharedWidgetStorageProvider).drainQuickCaptures();
    if (captures.isEmpty) return;
    final repo = ref.read(repositoryProvider);
    final existing = await repo.notes();
    for (final c in captures) {
      final dup = existing.any(
        (n) => n.title == c.text && n.body.isEmpty && n.isPending,
      );
      if (dup) continue;
      await repo.capture(title: c.text, body: '');
    }
    await reload();
  }

  /// Pull the full server catalog into the local mirror, push queued changes,
  /// then refresh the list. Used everywhere a user expects to see server-side
  /// notes (manual sync, after enrich) so AI-generated notes appear even when
  /// they predate this device's incremental cursor. Returns the number pushed,
  /// or -1 if the server was unreachable.
  Future<int> sync() async {
    if (_syncInFlight != null) {
      await _syncInFlight;
      return -1;
    }
    final completer = Completer<void>();
    _syncInFlight = completer.future;
    int pushed = -1;
    try {
      pushed = await ref.read(repositoryProvider).bootstrap();
      if (pushed >= 0) {
        ref.read(lastSyncedProvider.notifier).state = DateTime.now();
        _prefetchAttachments();
      }
    } catch (_) {
      pushed = -1;
    } finally {
      await reload(retries: 2);
      completer.complete();
      _syncInFlight = null;
    }
    return pushed;
  }

  /// Download missing attachment bytes in the background after sync.
  void _prefetchAttachments() {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    Future(() async {
      try {
        final cache = ref.read(attachmentCacheProvider);
        final notes = await ref.read(repositoryProvider).notes();
        final paths = <String>{};
        for (final note in notes) {
          paths.addAll(AttachmentCache.pathsFromNote(note));
        }
        for (final rel in paths) {
          if (await cache.exists(rel)) continue;
          try {
            final bytes = await client.downloadAttachment(rel);
            await cache.write(rel, bytes);
          } catch (_) {}
        }
      } catch (_) {}
    });
  }

  /// Backfill the full server catalog on demand (e.g. right after pairing or on
  /// app resume). Equivalent to [sync]; named for the call sites that conceptually
  /// "bootstrap" the local mirror.
  Future<int> bootstrap() => sync();

  Future<Note> capture({
    required String title,
    required String body,
    String? type,
    List<String>? tags,
    bool deferSync = false,
  }) async {
    Note? note;
    try {
      note = await ref.read(repositoryProvider).capture(
            title: title, body: body, type: type, tags: tags, deferSync: deferSync);
      return note;
    } finally {
      if (!deferSync) await reload();
    }
  }

  /// Saves the edit locally and queues a background server flush; returns as
  /// soon as the local mirror is updated (offline-first, never blocks on I/O).
  Future<void> updateNote(Note note) async {
    try {
      await ref.read(repositoryProvider).update(note);
    } finally {
      await reload(retries: 2);
    }
  }

  Future<void> delete(String path) async {
    final note = state.valueOrNull?.where((n) => n.path == path).firstOrNull;
    final deletedPaths = note != null
        ? AttachmentCache.pathsFromNote(note)
        : const <String>[];
    try {
      await ref.read(repositoryProvider).delete(path);
    } finally {
      await reload();
      await _evictUnreferencedAttachments(deletedPaths);
    }
  }

  Future<void> _evictUnreferencedAttachments(List<String> candidates) async {
    if (candidates.isEmpty) return;
    final cache = ref.read(attachmentCacheProvider);
    final notes = state.valueOrNull ?? const [];
    final referenced = {
      for (final n in notes) ...AttachmentCache.pathsFromNote(n),
    };
    for (final relPath in candidates) {
      if (!referenced.contains(relPath)) {
        await cache.delete(relPath);
      }
    }
  }

  /// Ask the server to enrich a note (idea image / photo caption). The
  /// generated note arrives on the next sync pull.
  Future<void> enrich(String path, {String kind = 'idea'}) async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    await client.enrich(path, kind: kind);
    await sync();
    final l = localizationsForAppLocale(ref.read(appLocaleProvider));
    await ref
        .read(notifierProvider)
        .jobComplete(l.notifEnrichmentReady, l.notifEnrichmentReadyBody);
  }
}

/// Deep-link request from the home-screen widget (tab switch + optional chat).
class HomeTabRequest {
  final int tabIndex;
  final String? chatSessionId;
  final bool newChat;
  const HomeTabRequest({
    required this.tabIndex,
    this.chatSessionId,
    this.newChat = false,
  });
}

class HomeTabRequestNotifier extends Notifier<HomeTabRequest?> {
  @override
  HomeTabRequest? build() => null;

  void openChat(String sessionId) {
    state = HomeTabRequest(tabIndex: 1, chatSessionId: sessionId);
  }

  void newChat() {
    state = const HomeTabRequest(tabIndex: 1, newChat: true);
  }

  /// Switch to the chat tab keeping the current session.
  void openChatTab() {
    state = const HomeTabRequest(tabIndex: 1);
  }

  /// Switch to the notes tab (e.g. from a "due for review" notification).
  void openNotesTab() {
    state = const HomeTabRequest(tabIndex: 0);
  }

  void clear() => state = null;
}

final homeTabRequestProvider =
    NotifierProvider<HomeTabRequestNotifier, HomeTabRequest?>(
  HomeTabRequestNotifier.new,
);

/// Widget tap deferred until [appNavigatorKey] is ready (cold start).
class PendingWidgetAction {
  final String action;
  final String? path;
  final String? sessionId;
  const PendingWidgetAction({
    required this.action,
    this.path,
    this.sessionId,
  });
}

class PendingWidgetActionNotifier extends Notifier<PendingWidgetAction?> {
  @override
  PendingWidgetAction? build() => null;

  void set(PendingWidgetAction action) => state = action;

  void clear() => state = null;
}

final pendingWidgetActionProvider =
    NotifierProvider<PendingWidgetActionNotifier, PendingWidgetAction?>(
  PendingWidgetActionNotifier.new,
);
