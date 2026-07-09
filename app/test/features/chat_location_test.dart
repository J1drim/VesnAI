import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vesnai_app/data/chat_location_service.dart';
import 'package:vesnai_app/data/location_context.dart';
import 'package:vesnai_app/features/chat/chat_sessions.dart';
import 'package:vesnai_app/providers.dart';

import '../helpers/chat_test_overrides.dart';

class _FixedChatLocationService extends ChatLocationService {
  final SavedLocation location;

  _FixedChatLocationService(this.location);

  @override
  Future<SavedLocation?> resolveForChat({
    required bool shareEnabled,
    SavedLocation? saved,
    DateTime? now,
  }) async {
    if (!shareEnabled) return null;
    return location;
  }
}

void main() {
  initFlutterTestBinding();

  test('send attaches location_context when share location is enabled', () async {
    final fixedLoc = SavedLocation(
      lat: 52.23,
      lon: 21.01,
      label: 'Warsaw',
      capturedAt: DateTime.utc(2026, 6, 30, 12),
    );
    var chatBody = <String, dynamic>{};
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/v1/chat/sessions' && req.method == 'GET') {
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }
      if (path == '/v1/chat/sessions' && req.method == 'POST') {
        return http.Response(
          jsonEncode({
            'id': 's1',
            'title': 'New chat',
            'created': '',
            'updated': '',
            'messages': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path == '/v1/chat') {
        chatBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'status': 'accepted',
            'session_id': 's1',
            'user_message_id': 'u1',
            'assistant_message_id': 'a1',
          }),
          202,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final container = ProviderContainer(
      overrides: [
        ...chatTestOverrides(httpClient: mock),
        chatLocationServiceProvider
            .overrideWith((ref) => _FixedChatLocationService(fixedLoc)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(shareLocationWithChatProvider.notifier).set(true);
    await Future<void>.delayed(Duration.zero);

    await container.read(chatControllerProvider.notifier).newChat();
    await container.read(chatControllerProvider.notifier).send('pogoda u mnie');

    expect(chatBody['location_context'], isNotNull);
    final loc = chatBody['location_context'] as Map<String, dynamic>;
    expect(loc['lat'], 52.23);
    expect(loc['label'], 'Warsaw');
  });

  test('send omits location_context when share location is disabled', () async {
    var chatBody = <String, dynamic>{};
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/v1/chat/sessions' && req.method == 'GET') {
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }
      if (path == '/v1/chat/sessions' && req.method == 'POST') {
        return http.Response(
          jsonEncode({
            'id': 's1',
            'title': 'New chat',
            'created': '',
            'updated': '',
            'messages': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path == '/v1/chat') {
        chatBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'status': 'accepted',
            'session_id': 's1',
            'assistant_message_id': 'a1',
          }),
          202,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final container = ProviderContainer(overrides: chatTestOverrides(httpClient: mock));
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    await container.read(chatControllerProvider.notifier).newChat();
    await container.read(chatControllerProvider.notifier).send('hello');

    expect(chatBody.containsKey('location_context'), isFalse);
  });
}
