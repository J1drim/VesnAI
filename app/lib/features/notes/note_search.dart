import '../../models/note.dart';

/// Client-side filter for title, body, and tags (case-insensitive substring).
bool noteMatchesQuery(Note note, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (note.title.toLowerCase().contains(q)) return true;
  if (note.body.toLowerCase().contains(q)) return true;
  for (final tag in note.tags) {
    if (tag.toLowerCase().contains(q)) return true;
  }
  return false;
}
