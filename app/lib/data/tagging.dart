/// On-device tag suggestion.
///
/// Behind an interface so it is mockable and so the heuristic baseline can later
/// be swapped for an on-device ML model without touching callers. Suggestions
/// are user-editable; accept/reject signals feed the server's self-tuning loop.
abstract class Tagger {
  /// Suggest a `(type, tags)` pair for the given note content.
  TagSuggestion suggest(String title, String body);
}

class TagSuggestion {
  final String type;
  final List<String> tags;
  const TagSuggestion(this.type, this.tags);
}

class HeuristicTagger implements Tagger {
  const HeuristicTagger();

  static final Map<String, List<String>> _keywords = {
    'idea': ['idea', 'maybe', 'what if', 'could', 'startup', 'invent'],
    'travel': ['trip', 'travel', 'flight', 'visit', 'vacation'],
    'todo': ['todo', 'buy', 'remember', 'task', 'call', 'email'],
    'photo': ['photo', 'picture', 'image', 'selfie'],
    'misc': [],
  };

  @override
  TagSuggestion suggest(String title, String body) {
    final text = '$title $body'.toLowerCase();
    final tags = <String>[];
    for (final entry in _keywords.entries) {
      if (entry.value.any(text.contains)) tags.add(entry.key);
    }
    if (tags.isEmpty) tags.add('misc');

    String type = 'Note';
    if (tags.contains('idea')) {
      type = 'Idea';
    } else if (tags.contains('photo')) {
      type = 'Photo';
    } else if (tags.contains('todo')) {
      type = 'Task';
    }
    return TagSuggestion(type, tags);
  }
}
