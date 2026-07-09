import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/connection_store.dart';
import 'package:vesnai_app/providers.dart';

void main() {
  test('InMemoryConnectionStore round-trips credentials and onboarding flag', () async {
    final store = InMemoryConnectionStore();
    expect(await store.load(), isNull);
    expect(await store.isOnboarded(), isFalse);

    await store.save(baseUrl: 'https://host:8443', token: 'tok', deviceId: 'dev1');
    final saved = await store.load();
    expect(saved?.baseUrl, 'https://host:8443');
    expect(saved?.token, 'tok');
    expect(saved?.deviceId, 'dev1');

    await store.setOnboarded();
    expect(await store.isOnboarded(), isTrue);

    await store.clear();
    expect(await store.load(), isNull);
  });

  test('ConnectionController hydrates from a saved connection', () async {
    final store = InMemoryConnectionStore();
    await store.save(baseUrl: 'https://host:8443', token: 'tok', deviceId: 'dev1');
    final container = ProviderContainer(
      overrides: [connectionStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    expect(container.read(serverConnectionProvider).isPaired, isFalse);
    await container.read(serverConnectionProvider.notifier).hydrate();

    final conn = container.read(serverConnectionProvider);
    expect(conn.isPaired, isTrue);
    expect(conn.token, 'tok');
    expect(conn.deviceId, 'dev1');
  });
}
