import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vesnai_app/data/notification_delivery.dart';

void main() {
  test(
    'independent consumers deduplicate; restart retains delivery; burst IDs are unique',
    () async {
      final dir = await Directory.systemTemp.createTemp('vesnai-delivery-test');
      addTearDown(() => dir.delete(recursive: true));
      final file = '${dir.path}/events.sqlite';
      final first = NotificationDelivery(sqlite3.open(file));
      final second = NotificationDelivery(sqlite3.open(file));
      final pending = Completer<void>();
      final started = Completer<void>();
      final work = first.deliver('same', (id) {
        started.complete();
        return pending.future;
      });
      await started.future;
      await expectLater(
        second.deliver('same', (_) async => fail('overlap delivered twice')),
        throwsStateError,
      );
      pending.complete();
      await work;
      first.close();
      second.close();
      final restarted = NotificationDelivery(sqlite3.open(file));
      addTearDown(restarted.close);
      await restarted.deliver(
        'same',
        (_) async => fail('restart delivered twice'),
      );
      final ids = <int>{};
      for (var i = 0; i < 1000; i++) {
        await restarted.deliver('burst-$i', (id) async {
          expect(ids.add(id), isTrue);
          expect(id, isNot(900001));
        });
      }
    },
  );

  test('failed delivery retries with the same stable native ID', () async {
    final ledger = NotificationDelivery(sqlite3.openInMemory());
    addTearDown(ledger.close);
    int? failedId;
    await expectLater(
      ledger.deliver('retry', (id) async {
        failedId = id;
        throw StateError('OS unavailable');
      }),
      throwsStateError,
    );
    await ledger.deliver('retry', (id) async => expect(id, failedId));
  });
}
