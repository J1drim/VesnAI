import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/features/chat/chat_message_content.dart';

void main() {
  const pollinations =
      'Oto obrazek:\n'
      '![cat](https://image.pollinations.ai/prompt/cat?width=1024)';

  test('hasExternalImageMarkdown detects pollinations', () {
    expect(ChatMessageDisplay.hasExternalImageMarkdown(pollinations), isTrue);
  });

  test('textForBubble strips image markdown and keeps intro', () {
    final out = ChatMessageDisplay.textForBubble(pollinations);
    expect(out, contains('Oto obrazek'));
    expect(out.toLowerCase(), isNot(contains('pollinations')));
  });

  test('textForBubble leaves plain text links', () {
    const text = 'See [Wikipedia](https://en.wikipedia.org/wiki/Cat).';
    expect(ChatMessageDisplay.textForBubble(text), text);
    expect(ChatMessageDisplay.hasExternalImageMarkdown(text), isFalse);
  });

  test('hasExternalImageMarkdown matches any https host', () {
    expect(
      ChatMessageDisplay.hasExternalImageMarkdown(
        '![x](https://cdn.example.com/a.png)',
      ),
      isTrue,
    );
  });

  test('shouldShowImagePending only when server queued FLUX', () {
    expect(
      ChatMessageDisplay.shouldShowImagePending(
        pendingImageGeneration: true,
        hasImageAttachment: false,
      ),
      isTrue,
    );
    expect(
      ChatMessageDisplay.shouldShowImagePending(
        pendingImageGeneration: false,
        hasImageAttachment: false,
      ),
      isFalse,
    );
    expect(
      ChatMessageDisplay.shouldShowImagePending(
        pendingImageGeneration: true,
        hasImageAttachment: true,
      ),
      isFalse,
    );
  });
}
