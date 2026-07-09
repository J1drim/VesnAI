import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/shared_storage.dart';

void main() {
  test('WidgetSnapshot v2 encodes chat recents', () {
    const snap = WidgetSnapshot(
      [WidgetNote(title: 'Idea', path: 'notes/x.md')],
      chatRecents: [WidgetChat(id: 's1', title: 'Trip planning')],
    );
    final decoded = WidgetSnapshot.decode(snap.encode());
    expect(decoded.recents.length, 1);
    expect(decoded.chatRecents.length, 1);
    expect(decoded.chatRecents.first.id, 's1');
  });
}
