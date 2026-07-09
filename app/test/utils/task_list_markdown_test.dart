import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/utils/task_list_markdown.dart';

void main() {
  test('countTaskListItems counts task lines only', () {
    const md = '''
Intro
- [ ] one
- normal bullet
- [x] two
''';
    expect(countTaskListItems(md), 2);
  });

  test('toggleTaskListItem checks unchecked item', () {
    const md = '- [ ] buy milk\n- [ ] buy eggs';
    final out = toggleTaskListItem(md, 1);
    expect(out, '- [ ] buy milk\n- [x] buy eggs');
  });

  test('toggleTaskListItem unchecks checked item', () {
    const md = '- [x] done';
    final out = toggleTaskListItem(md, 0);
    expect(out, '- [ ] done');
  });

  test('toggleTaskListItem preserves indent', () {
    const md = '  - [ ] nested';
    final out = toggleTaskListItem(md, 0);
    expect(out, '  - [x] nested');
  });

  test('toggleTaskListItem normalizes uppercase X', () {
    const md = '- [X] done';
    final out = toggleTaskListItem(md, 0);
    expect(out, '- [ ] done');
  });

  test('toggleTaskListItem returns unchanged for bad index', () {
    const md = '- [ ] only';
    expect(toggleTaskListItem(md, 3), md);
  });
}
