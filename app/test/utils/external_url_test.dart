import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/utils/external_url.dart';

void main() {
  test('isExternalUrl accepts http, https and mailto', () {
    expect(isExternalUrl('https://example.com/page'), isTrue);
    expect(isExternalUrl('http://example.com'), isTrue);
    expect(isExternalUrl('mailto:me@example.com'), isTrue);
    expect(isExternalUrl('HTTPS://EXAMPLE.COM'), isTrue);
    expect(isExternalUrl('  https://example.com  '), isTrue);
  });

  test('isExternalUrl rejects in-bundle and relative links', () {
    expect(isExternalUrl('attachments/photo.png'), isFalse);
    expect(isExternalUrl('notes/idea.md'), isFalse);
    expect(isExternalUrl('chat:abc/img.png'), isFalse);
    expect(isExternalUrl('javascript:alert(1)'), isFalse);
    expect(isExternalUrl('file:///etc/passwd'), isFalse);
    expect(isExternalUrl(''), isFalse);
  });
}
