import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesnai_app/data/shared_storage.dart';
import 'package:vesnai_app/models/note.dart';
import 'package:vesnai_app/providers.dart';

import '../helpers/chat_test_overrides.dart';

class CountingWidgetStorage extends InMemorySharedWidgetStorage {
  int writeCount = 0;

  @override
  Future<void> writeSnapshot(WidgetSnapshot snapshot) async {
    writeCount++;
    await super.writeSnapshot(snapshot);
  }
}

void main() {
  initFlutterTestBinding();

  test('notes reload preserves existing chatRecents in widget snapshot', () async {
    final storage = InMemorySharedWidgetStorage();
    await storage.writeSnapshot(WidgetSnapshot(
      const [WidgetNote(title: 'old note', path: 'notes/old.md')],
      chatRecents: [
        WidgetChat(id: 'c1', title: 'Chat one'),
      ],
    ));

    final container = ProviderContainer(
      overrides: [
        ...chatTestOverrides(httpClient: MockClient((_) async => http.Response('[]', 200))),
        sharedWidgetStorageProvider.overrideWith((ref) => storage),
      ],
    );
    addTearDown(container.dispose);

    await container.read(localStoreProvider).put(const Note(
          path: 'notes/new.md',
          title: 'New',
          body: 'body',
          updated: '2026-01-01',
        ));

    await container.read(notesProvider.notifier).reload();

    final snap = await storage.readSnapshot();
    expect(snap, isNotNull);
    expect(snap!.chatRecents.map((c) => c.id), ['c1']);
    expect(snap.recents.first.title, 'New');
  });

  test('identical reload skips duplicate widget snapshot write', () async {
    final storage = CountingWidgetStorage();
    final container = ProviderContainer(
      overrides: [
        ...chatTestOverrides(httpClient: MockClient((_) async => http.Response('[]', 200))),
        sharedWidgetStorageProvider.overrideWith((ref) => storage),
      ],
    );
    addTearDown(container.dispose);

    await container.read(localStoreProvider).put(const Note(
          path: 'notes/a.md',
          title: 'Alpha',
          body: 'body',
          updated: '2026-01-01',
        ));

    await container.read(notesProvider.notifier).reload();
    final writesAfterFirst = storage.writeCount;
    expect(writesAfterFirst, greaterThan(0));

    await container.read(notesProvider.notifier).reload();
    expect(storage.writeCount, writesAfterFirst);
  });

  test('widget snapshot caps recents at kWidgetRecentsLimit', () async {
    final storage = InMemorySharedWidgetStorage();
    final container = ProviderContainer(
      overrides: [
        ...chatTestOverrides(httpClient: MockClient((_) async => http.Response('[]', 200))),
        sharedWidgetStorageProvider.overrideWith((ref) => storage),
      ],
    );
    addTearDown(container.dispose);

    final store = container.read(localStoreProvider);
    for (var i = 0; i < 15; i++) {
      await store.put(Note(
        path: 'notes/note-$i.md',
        title: 'Note $i',
        body: 'body',
        updated: '2026-01-${(i + 1).toString().padLeft(2, '0')}',
      ));
    }

    await container.read(notesProvider.notifier).publishFullWidgetSnapshot();

    final snap = await storage.readSnapshot();
    expect(snap, isNotNull);
    expect(snap!.recents.length, kWidgetRecentsLimit);
  });
}
