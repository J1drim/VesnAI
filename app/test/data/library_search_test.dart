import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/drift/database.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/data/note_filter.dart';
import 'package:vesnai_app/models/note.dart';

void main() {
  test('upgrading an existing schema-8 mirror backfills search without changing notes', () async {
    final dir = Directory.systemTemp.createTempSync('vesnai-search-migration-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/mirror.sqlite');
    final old = VesnaiDatabase(NativeDatabase(file));
    await DriftNoteStore(old).put(const Note(path: 'notes/a.md', title: 'Existing library', baseVersion: 4));
    for (final trigger in ['note_search_insert', 'note_search_update', 'note_search_delete']) {
      await old.customStatement('DROP TRIGGER $trigger');
    }
    await old.customStatement('DROP TABLE note_search');
    await old.customStatement('PRAGMA user_version=8');
    await old.close();
    final upgraded = VesnaiDatabase(NativeDatabase(file));
    final notes = await DriftNoteStore(upgraded).search('exist');
    expect(notes.single.title, 'Existing library');
    expect(notes.single.baseVersion, 4);
    await upgraded.close();
  });
  late VesnaiDatabase db;
  late DriftNoteStore store;
  setUp(() {
    db = VesnaiDatabase(NativeDatabase.memory());
    store = DriftNoteStore(db);
  });
  tearDown(() => db.close());

  test(
    'FTS supports prefixes, literal query text, ranking and updates',
    () async {
      await store.put(
        const Note(
          path: 'notes/a.md',
          title: 'Creative work',
          body: 'a quiet moment',
        ),
      );
      await store.put(
        const Note(
          path: 'notes/b.md',
          title: 'A quiet moment',
          body: 'creative work',
        ),
      );
      expect((await store.search('creat wor')).first.path, 'notes/a.md');
      expect((await store.search('"creative" OR')).length, 0);
      expect(await store.search('" : *'), hasLength(2));
      await store.put(
        const Note(path: 'notes/a.md', title: 'Changed', body: 'different'),
      );
      expect((await store.search('creat')).single.path, 'notes/b.md');
      await store.remove('notes/b.md');
      expect(await store.search('creat'), isEmpty);
    },
  );

  test('filters run before pagination and pins sort first', () async {
    for (var i = 0; i < 8; i++) {
      await store.put(
        Note(
          path: 'notes/$i.md',
          title: 'Idea $i',
          type: 'Idea',
          tags: [i.isEven ? 'project' : 'other'],
        ).copyWith(archived: i < 3, pinned: i == 6),
      );
    }
    const filter = NoteFilter(
      scope: 'active',
      tag: 'project',
      types: {'Idea'},
      sort: 'title',
    );
    expect(
      (await store.search('', limit: 1, filter: filter)).single.path,
      'notes/6.md',
    );
    expect(
      (await store.search('', limit: 1, offset: 1, filter: filter)).single.path,
      'notes/4.md',
    );
    expect(
      await store.search('Idea', filter: const NoteFilter(scope: 'archive')),
      hasLength(3),
    );
    expect(
      await store.search('Idea', filter: const NoteFilter(scope: 'pinned')),
      hasLength(1),
    );
  });

  test('index rolls back with a failed note/cursor transaction', () async {
    await expectLater(
      store.transaction(() async {
        await store.put(const Note(path: 'notes/a.md', title: 'Transient'));
        await store.setCursor(7);
        throw StateError('disk failure');
      }),
      throwsStateError,
    );
    expect(await store.search('Transient'), isEmpty);
    expect(await store.getCursor(), 0);
  });

  test('Polish Unicode and diacritics are searchable offline', () async {
    await store.put(
      const Note(
        path: 'notes/a.md',
        title: 'Pomysł na podróż',
        tags: ['twórczość'],
      ),
    );
    expect(await store.search('podroz'), hasLength(1));
    expect(await store.search('twórcz'), hasLength(1));
  });
}
