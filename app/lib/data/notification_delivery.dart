import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Separate SQLite ledger: native completion/permission waits never lock notes.
/// SQLite write claims coordinate foreground/background isolates and processes.
class NotificationDelivery {
  final Database db;
  final DateTime Function() now;
  NotificationDelivery(this.db, {DateTime Function()? now})
    : now = now ?? DateTime.now {
    db.execute('PRAGMA busy_timeout=100');
    db.execute(
      '''CREATE TABLE IF NOT EXISTS delivery (
      id INTEGER PRIMARY KEY AUTOINCREMENT, event TEXT NOT NULL UNIQUE,
      delivered INTEGER NOT NULL DEFAULT 0, lease_until INTEGER NOT NULL DEFAULT 0)''',
    );
  }

  static Future<NotificationDelivery> open() async {
    final root = await getApplicationDocumentsDirectory();
    await root.create(recursive: true);
    return NotificationDelivery(
      sqlite3.open(p.join(root.path, 'notification_delivery.sqlite')),
    );
  }

  int? _claim(String event) {
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute('INSERT OR IGNORE INTO delivery(event) VALUES (?)', [event]);
      final row = db.select('SELECT * FROM delivery WHERE event = ?', [
        event,
      ]).single;
      if (row['delivered'] == 1) {
        db.execute('COMMIT');
        return null;
      }
      final timestamp = now().millisecondsSinceEpoch;
      if ((row['lease_until'] as int) > timestamp)
        throw StateError('Notification delivery already in progress');
      db.execute('UPDATE delivery SET lease_until = ? WHERE event = ?', [
        timestamp + 600000,
        event,
      ]);
      db.execute('COMMIT');
      final id = row['id'] as int;
      // 900001 is permanently reserved for retiring legacy reminders.
      return id >= 900001 ? id + 1 : id;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> deliver(String event, Future<void> Function(int id) show) async {
    final id = _claim(event);
    if (id == null) return;
    try {
      await show(id);
      db.execute(
        'UPDATE delivery SET delivered = 1, lease_until = 0 WHERE event = ?',
        [event],
      );
    } catch (_) {
      db.execute('UPDATE delivery SET lease_until = 0 WHERE event = ?', [
        event,
      ]);
      rethrow;
    }
  }

  void close() => db.close();
}
