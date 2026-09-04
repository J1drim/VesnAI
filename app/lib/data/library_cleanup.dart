import 'package:okf_dart/okf_dart.dart';

import '../models/note.dart';

class CleanupSuggestion {
  final String kind;
  final Note note;
  final String value;
  final String replacement;
  final bool editable;
  const CleanupSuggestion(
    this.kind,
    this.note,
    this.value, {
    this.replacement = '',
    this.editable = true,
  });
}

/// Explicit, deterministic suggestions; this scan never modifies the store.
List<CleanupSuggestion> inspectLibrary(List<Note> notes) {
  final results = <CleanupSuggestion>[];
  final known = notes.map((n) => n.path).toSet();
  final bodies = <String, Note>{};
  final tags = <String, Map<String, int>>{};
  for (final note in notes) {
    for (final tag in note.tags) {
      final counts = tags.putIfAbsent(tag.trim().toLowerCase(), () => {});
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }
  final canonical = <String, String>{};
  for (final entry in tags.entries) {
    final options = entry.value.keys.toList()
      ..sort((a, b) {
        final count = entry.value[b]!.compareTo(entry.value[a]!);
        return count == 0 ? a.compareTo(b) : count;
      });
    canonical[entry.key] = options.first.trim();
  }
  for (final note in notes) {
    if (note.archived ||
        note.path.contains('.conflict-') ||
        note.type == 'ChatTranscript')
      continue;
    final body = note.body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (body.length >= 20) {
      final previous = bodies[body];
      if (previous != null)
        results.add(CleanupSuggestion('duplicate', note, previous.path));
      else
        bodies[body] = note;
    }
    for (final tag in note.tags) {
      final replacement = canonical[tag.trim().toLowerCase()]!;
      if (tag != replacement && replacement.isNotEmpty)
        results.add(
          CleanupSuggestion('tag', note, tag, replacement: replacement),
        );
    }
    final concept = note.toConcept();
    final seen = <String>{};
    for (final entry in [
      ...concept.explicitLinks().map((href) => (href, true)),
      ...concept.bodyLinks().map((href) => (href, false)),
    ]) {
      final (href, explicit) = entry;
      if (Uri.tryParse(href)?.hasScheme == true || href.startsWith('#'))
        continue;
      final target = resolveLink(note.path, href, explicit);
      if (target.endsWith('.md') && !known.contains(target) && seen.add(href)) {
        results.add(
          CleanupSuggestion('broken', note, href, editable: explicit),
        );
      }
    }
  }
  return results;
}
