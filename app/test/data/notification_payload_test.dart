import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/notification_service.dart';
import 'package:vesnai_app/data/widget_actions.dart';
import 'package:vesnai_app/providers.dart';

void main() {
  // handleWidgetAction inspects appNavigatorKey.currentState, which needs a
  // widget binding even when no widget tree is built.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseNotificationPayload', () {
    test('parses note and critique payloads', () {
      final note = parseNotificationPayload(notePayload('notes/a.md'));
      expect(note!.kind, 'note');
      expect(note.path, 'notes/a.md');

      final critique = parseNotificationPayload(critiquePayload('notes/c.md'));
      expect(critique!.kind, 'critique');
      expect(critique.path, 'notes/c.md');
    });

    test('parses chat and due_review payloads', () {
      expect(parseNotificationPayload('chat')!.kind, 'chat');
      expect(parseNotificationPayload(kDueReviewPayload)!.kind, 'due_review');
    });

    test('rejects malformed payloads', () {
      expect(parseNotificationPayload(null), isNull);
      expect(parseNotificationPayload(''), isNull);
      expect(parseNotificationPayload('note:'), isNull);
      expect(parseNotificationPayload(':path'), isNull);
      expect(parseNotificationPayload('bogus:notes/a.md'), isNull);
    });
  });

  group('handleNotificationPayload routing', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('chat payload switches to the chat tab', () {
      handleNotificationPayload(container.read, 'chat');
      final req = container.read(homeTabRequestProvider);
      expect(req!.tabIndex, 1);
      expect(req.newChat, isFalse);
    });

    test('due_review payload switches to the notes tab', () {
      handleNotificationPayload(container.read, kDueReviewPayload);
      expect(container.read(homeTabRequestProvider)!.tabIndex, 0);
    });

    test('note payload defers an open_note action before navigator exists', () {
      handleNotificationPayload(container.read, notePayload('notes/a.md'));
      final pending = container.read(pendingWidgetActionProvider);
      expect(pending!.action, 'open_note');
      expect(pending.path, 'notes/a.md');
    });

    test('critique payload routes like a note open', () {
      handleNotificationPayload(container.read, critiquePayload('notes/c.md'));
      final pending = container.read(pendingWidgetActionProvider);
      expect(pending!.action, 'open_note');
      expect(pending.path, 'notes/c.md');
    });

    test('invalid payload changes nothing', () {
      handleNotificationPayload(container.read, 'bogus');
      expect(container.read(homeTabRequestProvider), isNull);
      expect(container.read(pendingWidgetActionProvider), isNull);
    });
  });
}
