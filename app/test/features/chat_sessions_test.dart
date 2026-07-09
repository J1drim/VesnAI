import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vesnai_app/data/chat_attachment.dart';
import 'package:vesnai_app/data/chat_store.dart';
import 'package:vesnai_app/features/chat/chat_sessions.dart';
import 'package:vesnai_app/providers.dart';

import '../helpers/chat_test_overrides.dart';

void main() {
  initFlutterTestBinding();

  test('newChat creates a session and send enqueues thinking assistant stub', () async {
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
        return http.Response(
          jsonEncode({
            'status': 'accepted',
            'session_id': 's1',
            'user_message_id': 'u1',
            'assistant_message_id': 'a1',
            'queue_position': 1,
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
    final controller = container.read(chatControllerProvider.notifier);

    await controller.newChat();
    expect(container.read(chatControllerProvider).activeId, 's1');

    await controller.send('make a note');

    final messages = container.read(chatControllerProvider).messages;
    expect(messages.map((m) => m.role), ['user', 'assistant']);
    expect(messages.first.content, 'make a note');
    expect(messages.last.isThinking, isTrue);
  });

  test('newChat single-flight reuses in-progress create and clears isCreatingChat', () async {
    var createCalls = 0;
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/v1/chat/sessions' && req.method == 'GET') {
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }
      if (path == '/v1/chat/sessions' && req.method == 'POST') {
        createCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response(
          jsonEncode({
            'id': 's-new',
            'title': 'New chat',
            'created': '',
            'updated': '',
            'messages': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final container = ProviderContainer(overrides: chatTestOverrides(httpClient: mock));
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(chatControllerProvider.notifier);

    final first = controller.newChat();
    expect(container.read(chatControllerProvider).isCreatingChat, isTrue);
    expect(container.read(chatControllerProvider).messages, isEmpty);
    final second = controller.newChat();
    await Future.wait([first, second]);

    expect(createCalls, 1);
    expect(container.read(chatControllerProvider).isCreatingChat, isFalse);
    expect(container.read(chatControllerProvider).activeId, 's-new');
  });

  test('send uploads attachments then posts attachment_refs to chat', () async {
    var uploadCalled = false;
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
      if (path == '/v1/chat/sessions/s1' && req.method == 'GET') {
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
      if (path == '/v1/chat/sessions/s1/attachments' && req.method == 'POST') {
        uploadCalled = true;
        return http.Response(
          jsonEncode({
            'path': 'abc-photo.png',
            'kind': 'image',
            'filename': 'photo.png',
            'mime': 'image/png',
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

    final container = ProviderContainer(overrides: chatTestOverrides(httpClient: mock));
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(chatControllerProvider.notifier);

    await controller.newChat();
    await controller.send(
      'what is this?',
      attachments: [
        PendingChatAttachment(
          filename: 'photo.png',
          bytes: Uint8List.fromList([1, 2, 3]),
          kind: 'image',
        ),
      ],
    );

    expect(uploadCalled, isTrue);
    expect(chatBody['attachment_refs'], isNotNull);
    final refs = chatBody['attachment_refs'] as List;
    expect(refs.first['path'], 'abc-photo.png');

    final messages = container.read(chatControllerProvider).messages;
    expect(messages.first.attachments, isNotEmpty);
    expect(messages.first.attachments.first.filename, 'photo.png');
  });

  test('send shows user bubble before server session check completes', () async {
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
      if (path == '/v1/chat/sessions/s1' && req.method == 'GET') {
        await Future<void>.delayed(const Duration(milliseconds: 200));
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
      if (path == '/v1/chat/sessions/s1/attachments' && req.method == 'POST') {
        return http.Response(
          jsonEncode({
            'path': 'abc-photo.png',
            'kind': 'image',
            'filename': 'photo.png',
            'mime': 'image/png',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path == '/v1/chat') {
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

    final container = ProviderContainer(overrides: chatTestOverrides(httpClient: mock));
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(chatControllerProvider.notifier);

    await controller.newChat();
    var bubbleVisible = false;
    final sendFuture = controller.send(
      'hello with photo',
      attachments: [
        PendingChatAttachment(
          filename: 'photo.png',
          bytes: Uint8List.fromList([1, 2, 3]),
          kind: 'image',
        ),
      ],
      onBubbleVisible: () => bubbleVisible = true,
    );
    while (!bubbleVisible) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(bubbleVisible, isTrue);
    expect(container.read(chatControllerProvider).messages, isNotEmpty);
    expect(container.read(chatControllerProvider).messages.first.content,
        'hello with photo');
    await sendFuture;
  });

  test('send keeps bubble when server session check fails', () async {
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
      if (path == '/v1/chat/sessions/s1' && req.method == 'GET') {
        return http.Response('server error', 500);
      }
      return http.Response('not found', 404);
    });

    final container = ProviderContainer(overrides: chatTestOverrides(httpClient: mock));
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(chatControllerProvider.notifier);

    await controller.newChat();
    await expectLater(
      controller.send(
        'fragile send',
        attachments: [
          PendingChatAttachment(
            filename: 'photo.png',
            bytes: Uint8List.fromList([1, 2, 3]),
            kind: 'image',
          ),
        ],
      ),
      throwsA(isA<ChatSendException>()),
    );

    final messages = container.read(chatControllerProvider).messages;
    expect(messages, isNotEmpty);
    expect(messages.first.content, 'fragile send');
    expect(messages.first.isPendingSend, isTrue);
  });

  test('switchTo preserves sending message not yet on server', () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/v1/chat/sessions/s1' && req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'id': 's1',
            'title': 'Chat',
            'created': '',
            'updated': '',
            'messages': [
              {
                'id': 'a1',
                'role': 'assistant',
                'content': 'Hi',
                'ts': '2026-01-01T00:00:00Z',
                'attachments': [],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('[]', 200, headers: {'content-type': 'application/json'});
    });

    final container = ProviderContainer(overrides: chatTestOverrides(httpClient: mock));
    addTearDown(container.dispose);
    final store = container.read(chatStoreProvider);
    await store.upsertSession(StoredChatSession(
      id: 's1',
      title: 'Chat',
      created: '',
      updated: '',
    ));
    await store.appendMessage(
      sessionId: 's1',
      role: 'user',
      content: 'still sending',
      syncState: 2,
    );
    await store.appendMessage(sessionId: 's1', role: 'assistant', content: 'Hi');

    final controller = container.read(chatControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    await controller.switchTo('s1', forceRefresh: true);

    final messages = container.read(chatControllerProvider).messages;
    expect(messages.any((m) => m.content == 'still sending'), isTrue);
    expect(messages.any((m) => m.content == 'Hi'), isTrue);
  });

  test('retrySend delivers failed user message', () async {
    var chatCalls = 0;
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
      if (path == '/v1/chat/sessions/s1' && req.method == 'GET') {
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
        chatCalls++;
        if (chatCalls == 1) {
          return http.Response('fail', 500);
        }
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

    final container = ProviderContainer(overrides: chatTestOverrides(httpClient: mock));
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(chatControllerProvider.notifier);
    final store = container.read(chatStoreProvider);

    await controller.newChat();
    await expectLater(
      controller.send('retry me'),
      throwsA(isA<ChatSendException>()),
    );

    final failed = container.read(chatControllerProvider).messages.first;
    expect(failed.isPendingSend, isTrue);
    final failedId = failed.id;

    await controller.retrySend(failedId);

    final messages = container.read(chatControllerProvider).messages;
    expect(messages.any((m) => m.id == 'u1' || m.content == 'retry me'), isTrue);
    expect(messages.any((m) => m.isThinking), isTrue);
    final stored = await store.messageById('u1');
    expect(stored?.syncState, 0);
  });

  test('switchTo keeps local messages when server fetch fails', () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/v1/chat/sessions/s1' && req.method == 'GET') {
        return http.Response('error', 500);
      }
      return http.Response('[]', 200, headers: {'content-type': 'application/json'});
    });

    final container = ProviderContainer(overrides: chatTestOverrides(httpClient: mock));
    addTearDown(container.dispose);
    final store = container.read(chatStoreProvider);
    await store.upsertSession(StoredChatSession(
      id: 's1',
      title: 'Chat',
      created: '',
      updated: '',
    ));
    await store.appendMessage(sessionId: 's1', role: 'user', content: 'hello');

    final controller = container.read(chatControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    await controller.switchTo('s1', forceRefresh: true);

    final messages = container.read(chatControllerProvider).messages;
    expect(messages, isNotEmpty);
    expect(messages.first.content, 'hello');
  });

  test('switchTo keeps local messages when server returns empty list', () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/v1/chat/sessions/s1' && req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'id': 's1',
            'title': 'Chat',
            'created': '',
            'updated': '',
            'messages': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('[]', 200, headers: {'content-type': 'application/json'});
    });

    final container = ProviderContainer(overrides: chatTestOverrides(httpClient: mock));
    addTearDown(container.dispose);
    final store = container.read(chatStoreProvider);
    await store.upsertSession(StoredChatSession(
      id: 's1',
      title: 'Chat',
      created: '',
      updated: '',
    ));
    await store.appendMessage(sessionId: 's1', role: 'user', content: 'hello');

    final controller = container.read(chatControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    await controller.switchTo('s1', forceRefresh: true);

    final messages = container.read(chatControllerProvider).messages;
    expect(messages, isNotEmpty);
    expect(messages.first.content, 'hello');
  });
}
