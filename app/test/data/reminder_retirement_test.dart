import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vesnai_app/data/notification_delivery.dart';
import 'package:vesnai_app/data/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var failCancellation = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    failCancellation = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'cancel' && failCancellation) {
            throw PlatformException(code: 'temporarily_unavailable');
          }
          return true;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'retires only the legacy reminder without requesting permissions',
    () async {
      final notifier = LocalNotifier();
      expect(await retireLegacyReminder(notifier), isTrue);
      expect(await retireLegacyReminder(notifier), isTrue);
      expect(calls.map((c) => c.method), ['initialize', 'cancel', 'cancel']);
      for (final call in calls.where((c) => c.method == 'cancel')) {
        expect((call.arguments as Map)['id'], 900001);
      }
    },
  );

  test('failed offline cleanup can retry on the next resume', () async {
    final notifier = LocalNotifier();
    failCancellation = true;
    expect(await retireLegacyReminder(notifier), isFalse);
    failCancellation = false;
    expect(await retireLegacyReminder(notifier), isTrue);
    expect(calls.where((c) => c.method == 'cancel').length, 2);
  });

  test(
    'disabled completion alerts do not request permission; enabled bursts use distinct IDs',
    () async {
      SharedPreferences.setMockInitialValues({
        'library_preferences': '{"notifications":false}',
      });
      final ledger = NotificationDelivery(sqlite3.openInMemory());
      addTearDown(ledger.close);
      final notifier = LocalNotifier(delivery: ledger);
      await notifier.jobComplete('Muted', 'Work finished', eventId: 'muted');
      expect(calls, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('library_preferences', '{"notifications":true}');
      await notifier.jobComplete('A', 'Work finished', eventId: 'a');
      await notifier.jobComplete('B', 'Work finished', eventId: 'b');
      await notifier.jobComplete('A', 'Work finished', eventId: 'a');
      final shown = calls.where((c) => c.method == 'show').toList();
      expect(shown, hasLength(2));
      expect(
        (shown[0].arguments as Map)['id'],
        isNot((shown[1].arguments as Map)['id']),
      );
    },
  );
}
