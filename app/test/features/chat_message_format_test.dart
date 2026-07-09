import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/features/chat/chat_message_format.dart';

void main() {
  testWidgets('formatChatMessageSentAt shows time for today', (tester) async {
    final now = DateTime(2026, 3, 15, 14, 30);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Text(
            formatChatMessageSentAt(context, now),
          ),
        ),
      ),
    );
    expect(find.textContaining('2:30'), findsOneWidget);
  });

  test('parseChatMessageSentAt parses ISO timestamps', () {
    final parsed = parseChatMessageSentAt('2026-03-15T12:00:00.000Z');
    expect(parsed, isNotNull);
  });
}
