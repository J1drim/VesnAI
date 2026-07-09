import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'features/chat/chat_sessions.dart';
import 'providers.dart';
import 'data/attachment_cache.dart';
import 'data/background_poll.dart';
import 'data/chat_attachment_cache.dart';
import 'data/graph_layout_store.dart';
import 'data/http_client_factory.dart';
import 'data/local_store.dart';
import 'data/notification_service.dart';
import 'data/notifications_feed.dart';
import 'data/shared_storage.dart';
import 'data/voice_cache.dart';
import 'data/widget_actions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw under the system bars (Android 15+ edge-to-edge); screens use SafeArea.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final httpClient = await createPlatformHttpClient();
  final attachmentCache = await AttachmentCache.open();
  final chatAttachmentCache = await ChatAttachmentCache.open();
  final voiceCache = await VoiceCache.open();
  final sharedPrefs = await SharedPreferences.getInstance();
  // Durable SQLite store, native widget bridge, and OS notifications on device.
  late final ProviderContainer container;
  final localNotifier = LocalNotifier(
    onTap: (payload) => handleNotificationPayload(container.read, payload),
  );
  container = ProviderContainer(
    overrides: [
      graphLayoutStoreProvider.overrideWith(
        (ref) => SharedPreferencesGraphLayoutStore(sharedPrefs),
      ),
      httpClientProvider.overrideWith((ref) {
        ref.onDispose(httpClient.close);
        return httpClient;
      }),
      attachmentCacheProvider.overrideWith((ref) => attachmentCache),
      chatAttachmentCacheProvider.overrideWith((ref) => chatAttachmentCache),
      voiceCacheProvider.overrideWith((ref) => voiceCache),
      localStoreProvider.overrideWith((ref) => DriftNoteStore(ref.watch(vesnaiDatabaseProvider))),
      sharedWidgetStorageProvider.overrideWith((ref) => const PlatformSharedWidgetStorage()),
      notifierProvider.overrideWith((ref) => localNotifier),
    ],
  );
  // Route home-screen widget taps (deep links) into the app.
  registerWidgetActionHandler(container);
  // Restore any saved pairing + onboarding flag before the first frame.
  await container.read(serverConnectionProvider.notifier).hydrate();
  await container.read(appLocaleProvider.notifier).hydrate();
  await container.read(assistantLanguageProvider.notifier).hydrate();
  await container.read(shareLocationWithChatProvider.notifier).hydrate();
  await container.read(savedChatLocationProvider.notifier).hydrate();
  final onboarded = await container.read(connectionStoreProvider).isOnboarded();
  container.read(onboardedProvider.notifier).state = onboarded;
  // Pull in any quick captures made from a home-screen widget while closed.
  await container.read(notesProvider.notifier).ingestQuickCaptures();
  // Eagerly hydrate chat from local Drift so widget gets both notes + chats.
  await container.read(chatControllerProvider.notifier).publishWidgetFromLocalStore();
  await container.read(notesProvider.notifier).publishFullWidgetSnapshot();
  // Backfill the server catalog in the background when already paired, so
  // existing/AI-generated notes appear without waiting for a manual sync.
  if (container.read(serverConnectionProvider).isPaired) {
    unawaited(container.read(notesProvider.notifier).bootstrap());
    // Surface any image-ready notifications queued while the app was closed.
    unawaited(container.read(notificationsServiceProvider).drain());
    // Poll the notification feed periodically while the app is closed
    // (Android WorkManager / iOS BGTaskScheduler; no-op on desktop).
    unawaited(registerBackgroundPolling());
  }
  // If a notification tap launched the app (cold start), route it once the
  // first frame is up and the navigator exists.
  unawaited(localNotifier.launchPayload().then((payload) {
    if (payload == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      handleNotificationPayload(container.read, payload);
    });
  }));
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const VesnaiApp(),
    ),
  );
}
