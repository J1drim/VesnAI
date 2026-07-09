import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/features/graph/graph_screen.dart';
import 'package:vesnai_app/models/note.dart';
import 'package:vesnai_app/providers.dart';

void main() {
  test('graphProvider builds from local notes without server', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final store = container.read(localStoreProvider);
    await store.put(const Note(
      path: 'notes/a.md',
      title: 'Alpha',
      links: ['notes/b.md'],
    ));
    await store.put(const Note(path: 'notes/b.md', title: 'Beta'));

    await container.read(notesProvider.future);
    final graph = container.read(graphProvider);

    expect((graph['nodes'] as List).length, 2);
    expect((graph['edges'] as List).length, 1);
  });

  test('reload keeps previous notes visible while refreshing', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(notesProvider.notifier).capture(title: 'One', body: '');
    final before = container.read(notesProvider);
    expect(before.hasValue, isTrue);
    expect(before.value!.length, 1);

    final reloadFuture = container.read(notesProvider.notifier).reload();
    final during = container.read(notesProvider);
    expect(during.isLoading, isTrue);
    expect(during.hasValue, isTrue);
    expect(during.value!.length, 1);

    await reloadFuture;
    expect(container.read(notesProvider).value!.length, 1);
  });
}
