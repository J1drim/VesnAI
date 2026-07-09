import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Local note mirror. Always rebuildable from the server's OKF bundle, so it is
/// never the source of truth - just an offline-first cache + sync queue.
class NoteRows extends Table {
  TextColumn get path => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get type => text().withDefault(const Constant('Note'))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get origin => text().withDefault(const Constant('user'))();
  TextColumn get linksJson => text().withDefault(const Constant('[]'))();
  TextColumn get attachmentsJson => text().withDefault(const Constant('[]'))();
  TextColumn get source => text().withDefault(const Constant(''))();
  TextColumn get updated => text().withDefault(const Constant(''))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  TextColumn get doneAt => text().withDefault(const Constant(''))();
  IntColumn get syncState => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {path};
}

/// Single-row key/value table for sync bookkeeping (the pull cursor).
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class ChatSessionRows extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant('New chat'))();
  TextColumn get created => text().withDefault(const Constant(''))();
  TextColumn get updated => text().withDefault(const Constant(''))();
  IntColumn get syncState => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class ChatMessageRows extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get role => text()();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get ts => text().withDefault(const Constant(''))();
  TextColumn get ttsAudioPath => text().withDefault(const Constant(''))();
  TextColumn get attachmentsJson => text().withDefault(const Constant('[]'))();
  IntColumn get syncState => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [NoteRows, SyncMeta, ChatSessionRows, ChatMessageRows])
class VesnaiDatabase extends _$VesnaiDatabase {
  VesnaiDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(chatSessionRows);
            await m.createTable(chatMessageRows);
          }
          if (from < 3) {
            await m.addColumn(noteRows, noteRows.attachmentsJson);
            await m.addColumn(chatMessageRows, chatMessageRows.ttsAudioPath);
          }
          if (from < 4) {
            await m.addColumn(chatMessageRows, chatMessageRows.attachmentsJson);
          }
          if (from < 5) {
            await m.addColumn(noteRows, noteRows.source);
          }
          if (from < 6) {
            await m.addColumn(noteRows, noteRows.version);
          }
          if (from < 7) {
            await m.addColumn(noteRows, noteRows.done);
            await m.addColumn(noteRows, noteRows.doneAt);
          }
        },
      );

  static LazyDatabase _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'vesnai_notes.sqlite'));
      return NativeDatabase.createInBackground(
        file,
        setup: (rawDb) {
          rawDb.execute('PRAGMA journal_mode=WAL;');
          rawDb.execute('PRAGMA busy_timeout=5000;');
        },
      );
    });
  }
}
