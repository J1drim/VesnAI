import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n_outside_widgets.dart';
import 'notification_delivery.dart';

/// Well-known notification ids (scheduled notifications must be stable so
/// re-scheduling replaces instead of stacking).
const int kDueReviewNotificationId = 900001;

/// Payload conventions shared by foreground, scheduled, and background-poll
/// notifications. See [parseNotificationPayload].
String notePayload(String path) => 'note:$path';
String critiquePayload(String path) => 'critique:$path';
const String kDueReviewPayload = 'due_review';

/// Parsed deep-link target of a notification tap.
class NotificationTarget {
  /// One of: `note`, `critique`, `due_review`, `chat`.
  final String kind;
  final String? path;
  const NotificationTarget(this.kind, [this.path]);
}

NotificationTarget? parseNotificationPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  if (payload == kDueReviewPayload) {
    return const NotificationTarget('due_review');
  }
  if (payload == 'chat') return const NotificationTarget('chat');
  final sep = payload.indexOf(':');
  if (sep <= 0) return null;
  final kind = payload.substring(0, sep);
  final path = payload.substring(sep + 1);
  if (path.isEmpty) return null;
  if (kind == 'note' || kind == 'critique') {
    return NotificationTarget(kind, path);
  }
  return null;
}

/// Thin wrapper over OS notifications, used to alert the user when a long
/// background job finishes. Legacy reminder cancellation stays available for upgrades.
abstract class JobNotifier {
  Future<void> jobComplete(
    String title,
    String body, {
    String? payload,
    String? eventId,
  });

  Future<void> cancelScheduled(int id);

  /// Payload of the notification that launched the app (cold start), if any.
  Future<String?> launchPayload();
}

class LocalNotifier implements JobNotifier {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;
  bool _permissionsRequested = false;
  Future<NotificationDelivery>? _delivery;

  /// Invoked when the user taps a notification while the app is running.
  final void Function(String payload)? onTap;

  LocalNotifier({this.onTap, NotificationDelivery? delivery})
    : _delivery = delivery == null ? null : Future.value(delivery);

  Future<void> _init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const windows = WindowsInitializationSettings(
      appName: 'VesnAI',
      appUserModelId: 'ai.vesnai.app',
      // Stable GUID identifying this app to the Windows notification platform.
      guid: 'a9d3c3e1-6f6a-4c1e-9b1e-2d6c1a7e5b42',
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
        windows: windows,
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onTap?.call(payload);
      },
    );
    _inited = true;
  }

  // Channel name/description appear in the Android system settings UI, so
  // they follow the app language preference.
  static Future<NotificationDetails> _jobDetails() async {
    final l = await localizationsFromPreferences();
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'vesnai_jobs',
        l.channelBgJobs,
        channelDescription: l.channelBgJobsDesc,
        importance: Importance.defaultImportance,
        onlyAlertOnce: true,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    );
  }

  @override
  Future<void> jobComplete(
    String title,
    String body, {
    String? payload,
    String? eventId,
  }) async {
    final delivery = await (_delivery ??= NotificationDelivery.open());
    final event =
        eventId ??
        'local-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    await delivery.deliver(event, (id) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final preferences =
          jsonDecode(prefs.getString('library_preferences') ?? '{}') as Map;
      if (preferences['notifications'] == false) return;
      await _show(id, title, body, payload: payload);
    });
  }

  Future<void> _show(
    int id,
    String title,
    String body, {
    String? payload,
  }) async {
    await _init();
    if (!_permissionsRequested) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      _permissionsRequested = true;
    }
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: await _jobDetails(),
      payload: payload,
    );
  }

  @override
  Future<void> cancelScheduled(int id) async {
    await _init();
    await _plugin.cancel(id: id);
  }

  @override
  Future<String?> launchPayload() async {
    await _init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse?.payload;
  }
}

/// No-op notifier for tests and unsupported platforms.
class NoopNotifier implements JobNotifier {
  const NoopNotifier();

  @override
  Future<void> jobComplete(
    String title,
    String body, {
    String? payload,
    String? eventId,
  }) async {}

  @override
  Future<void> cancelScheduled(int id) async {}

  @override
  Future<String?> launchPayload() async => null;
}

/// Run on every launch/resume, even unpaired. A failed cancellation is retried
/// next time; it never prevents capture or requests notification permission.
Future<bool> retireLegacyReminder(JobNotifier notifier) async {
  try {
    await notifier.cancelScheduled(kDueReviewNotificationId);
    return true;
  } catch (error) {
    debugPrint('Legacy reminder cleanup will retry: $error');
    return false;
  }
}
