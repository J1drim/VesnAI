import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okf_dart/okf_dart.dart';
import 'package:vesnai_app/data/drift/database.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/models/note.dart';

void main() {
  late VesnaiDatabase db;
  late DriftNoteStore store;

  setUp(() {
    db = VesnaiDatabase(NativeDatabase.memory());
    store = DriftNoteStore(db);
  });
  tearDown(() => db.close());

  test('put / get / all / remove round-trip', () async {
    await store.put(const Note(
      path: 'notes/a.md',
      title: 'Alpha',
      body: 'hello',
      tags: ['x', 'y'],
      origin: Origin.generated,
      updated: '2024-01-01',
      syncState: SyncState.pendingCreate,
    ));

    final all = await store.all();
    expect(all, hasLength(1));

    final got = await store.get('notes/a.md');
    expect(got!.title, 'Alpha');
    expect(got.tags, ['x', 'y']);
    expect(got.origin, Origin.generated);
    expect(got.syncState, SyncState.pendingCreate);

    await store.remove('notes/a.md');
    expect(await store.get('notes/a.md'), isNull);
  });

  test('pending() returns only unsynced notes', () async {
    await store.put(const Note(path: 'a.md', syncState: SyncState.synced));
    await store.put(const Note(path: 'b.md', syncState: SyncState.pendingUpdate));
    final pending = await store.pending();
    expect(pending.map((n) => n.path), ['b.md']);
  });

  test('attachments round-trip through Drift', () async {
    await store.put(const Note(
      path: 'notes/photo.md',
      attachments: ['attachments/pic.png'],
    ));
    final got = await store.get('notes/photo.md');
    expect(got!.attachments, ['attachments/pic.png']);
  });

  test('done and doneAt round-trip through Drift', () async {
    await store.put(const Note(
      path: 'notes/shopping.md',
      title: 'Shopping list',
      done: true,
      doneAt: '2026-07-08T08:00:00Z',
    ));
    final got = await store.get('notes/shopping.md');
    expect(got!.done, isTrue);
    expect(got.doneAt, '2026-07-08T08:00:00Z');

    // Reopening clears both fields.
    await store.put(got.copyWith(done: false, doneAt: ''));
    final reopened = await store.get('notes/shopping.md');
    expect(reopened!.done, isFalse);
    expect(reopened.doneAt, isEmpty);
  });

  test('pending() retains done for sync push', () async {
    await store.put(const Note(
      path: 'notes/task.md',
      done: true,
      doneAt: '2026-07-08T08:00:00Z',
      syncState: SyncState.pendingUpdate,
    ));
    final pending = await store.pending();
    expect(pending.single.done, isTrue);
    expect(pending.single.doneAt, '2026-07-08T08:00:00Z');
  });

  test('sync cursor persists', () async {
    expect(await store.getCursor(), 0);
    await store.setCursor(42);
    expect(await store.getCursor(), 42);
  });
}
