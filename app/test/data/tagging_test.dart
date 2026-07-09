import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/tagging.dart';

void main() {
  const tagger = HeuristicTagger();

  test('detects idea', () {
    final s = tagger.suggest('A startup idea', 'what if we build an app');
    expect(s.type, 'Idea');
    expect(s.tags, contains('idea'));
  });

  test('detects todo/task', () {
    final s = tagger.suggest('Shopping', 'remember to buy milk');
    expect(s.tags, contains('todo'));
    expect(s.type, 'Task');
  });

  test('falls back to misc', () {
    final s = tagger.suggest('Random', 'the weather is nice');
    expect(s.tags, ['misc']);
    expect(s.type, 'Note');
  });
}
