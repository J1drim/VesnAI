import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/widget_actions.dart';

void main() {
  test('isValidWidgetNotePath rejects traversal and reserved paths', () {
    expect(isValidWidgetNotePath('notes/a.md'), isTrue);
    expect(isValidWidgetNotePath('../notes/evil.md'), isFalse);
    expect(isValidWidgetNotePath('log.md'), isFalse);
    expect(isValidWidgetNotePath('memory/user.md'), isFalse);
  });
}
