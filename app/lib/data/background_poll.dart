import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../l10n/l10n_outside_widgets.dart';
import 'api_client.dart';
import 'connection_store.dart';
import 'http_client_factory.dart';
import 'notification_service.dart';

/// Periodic background poll of the server notification feed so events (Marena
/// critiques, generated images, finished chat turns) surface as OS
/// notifications while the app is closed. No cloud push involved: the phone
/// polls the paired LAN server directly.
///
/// Android runs this via WorkManager (~15 min minimum). iOS uses
/// BGTaskScheduler and is best-effort (the OS decides when to run). Desktop
/// platforms are not supported by workmanager; there the in-app foreground
/// polling in [NotificationsService] covers the running-app case.
const String kBackgroundPollTask = 'ai.vesnai.notificationPoll';

bool get backgroundPollSupported => Platform.isAndroid || Platform.isIOS;

/// Entry point invoked by the OS in a background isolate.
@pragma('vm:entry-point')
void backgroundPollDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      return await runBackgroundNotificationPoll();
    } catch (e) {
      debugPrint('Background poll failed: $e');
      return true; // Don't trigger platform retry/backoff for transient errors.
    }
  });
}

/// Register the periodic poll. Safe to call on every launch (replaces the
/// existing registration).
Future<void> registerBackgroundPolling() async {
  if (!backgroundPollSupported) return;
  await Workmanager().initialize(backgroundPollDispatcher);
  await Workmanager().registerPeriodicTask(
    kBackgroundPollTask,
    kBackgroundPollTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

Future<void> cancelBackgroundPolling() async {
  if (!backgroundPollSupported) return;
  await Workmanager().cancelByUniqueName(kBackgroundPollTask);
}

/// Poll unread notifications and raise one OS notification per item, then ack.
/// Runs in a background isolate: reads credentials straight from secure
/// storage (no Riverpod container exists here).
Future<bool> runBackgroundNotificationPoll({
  ConnectionStore? store,
  VesnaiApiClient? client,
  JobNotifier? notifier,
}) async {
  final saved = await (store ?? SecureConnectionStore()).load();
  if (saved == null && client == null) return true; // Not paired.
  final api = client ??
      VesnaiApiClient(
        baseUrl: Uri.parse(saved!.baseUrl),
        token: saved.token,
        client: await createPlatformHttpClient(),
      );
  final notify = notifier ?? LocalNotifier();
  final List<Map<String, dynamic>> items;
  try {
    items = await api.listNotifications(unreadOnly: true);
  } catch (_) {
    return true; // Server unreachable; try again on the next slot.
  }
  if (items.isEmpty) return true;
  final l = await localizationsFromPreferences();
  for (final n in items) {
    final kind = n['kind'] as String? ?? '';
    final title = (n['title'] as String?)?.trim();
    final notePath = n['note_path'] as String?;
    final sourcePath = n['source_path'] as String?;
    switch (kind) {
      case 'critique_ready':
        await notify.jobComplete(
          title?.isNotEmpty == true ? title! : l.notifMarenaCritique,
          l.notifMarenaCritiqueBody,
          payload: notePath != null && notePath.isNotEmpty
              ? critiquePayload(notePath)
              : null,
        );
      case 'chat_turn_ready':
        await notify.jobComplete(
          title?.isNotEmpty == true ? title! : l.notifVesnaiReplied,
          l.notifVesnaiRepliedBody,
          payload: 'chat',
        );
      case 'chat_image_ready':
        await notify.jobComplete(
          title?.isNotEmpty == true ? title! : l.notifChatImageReady,
          l.notifChatImageReadyBody,
          payload: 'chat',
        );
      case 'chat_turn_failed':
      case 'chat_image_failed':
        // Failures are surfaced in-app; skip OS noise while closed.
        break;
      default:
        await notify.jobComplete(
          title?.isNotEmpty == true ? title! : l.notifImageReady,
          l.notifImageReadyBody,
          payload: sourcePath != null && sourcePath.isNotEmpty
              ? notePayload(sourcePath)
              : null,
        );
    }
  }
  final ids = items.map((e) => e['id']).whereType<String>().toList(growable: false);
  if (ids.isNotEmpty) {
    try {
      await api.ackNotifications(ids);
    } catch (_) {}
  }
  return true;
}
