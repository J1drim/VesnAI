import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/l10n_outside_widgets.dart';

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
  if (payload == kDueReviewPayload) return const NotificationTarget('due_review');
  if (payload == 'chat') return const NotificationTarget('chat');
  final sep = payload.indexOf(':');
  if (sep <= 0) return null;
  final kind = payload.substring(0, sep);
  final path = payload.substring(sep + 1);
  if (path.isEmpty) return null;
  if (kind == 'note' || kind == 'critique') return NotificationTarget(kind, path);
  return null;
}

/// Thin wrapper over OS notifications, used to alert the user when a long
/// background job (web search, enrichment) finishes and to schedule offline
/// reminders. Behind an interface so tests can substitute a no-op.
abstract class JobNotifier {
  Future<void> jobComplete(String title, String body, {String? payload});

  /// Schedule (or replace) a daily reminder that fires at [hour]:[minute]
  /// local time, entirely offline.
  Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  });

  Future<void> cancelScheduled(int id);

  /// Payload of the notification that launched the app (cold start), if any.
  Future<String?> launchPayload();
}

class LocalNotifier implements JobNotifier {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  /// Invoked when the user taps a notification while the app is running.
  final void Function(String payload)? onTap;

  LocalNotifier({this.onTap});

  Future<void> _init() async {
    if (_inited) return;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // Keep the default (UTC) location; scheduled times shift but still fire.
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
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
    // Android 13+ runtime permission.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
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
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    );
  }

  static Future<NotificationDetails> _reminderDetails() async {
    final l = await localizationsFromPreferences();
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'vesnai_reminders',
        l.channelReminders,
        channelDescription: l.channelRemindersDesc,
        importance: Importance.defaultImportance,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    );
  }

  @override
  Future<void> jobComplete(String title, String body, {String? payload}) async {
    await _init();
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
      title: title,
      body: body,
      notificationDetails: await _jobDetails(),
      payload: payload,
    );
  }

  @override
  Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    await _init();
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: await _reminderDetails(),
        // Inexact keeps us off the exact-alarm permission; a review reminder
        // does not need minute precision.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Could not schedule reminder: $e');
    }
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
  Future<void> jobComplete(String title, String body, {String? payload}) async {}

  @override
  Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {}

  @override
  Future<void> cancelScheduled(int id) async {}

  @override
  Future<String?> launchPayload() async => null;
}
