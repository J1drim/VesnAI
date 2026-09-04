import '../models/note.dart';

class NoteFilter {
  final String scope;
  final String tag;
  final String sort;
  final Set<String> types;
  final bool showDone;
  final bool libraryOnly;
  const NoteFilter({
    this.scope = 'all',
    this.tag = '',
    this.sort = 'relevance',
    this.types = const {},
    this.showDone = true,
    this.libraryOnly = false,
  });

  bool matches(Note n) =>
      (!libraryOnly ||
          (!n.path.contains('.conflict-') &&
              n.type != 'ChatTranscript' &&
              !(n.source.isNotEmpty &&
                  {'GeneratedImage', 'GeneratedCaption'}.contains(n.type)))) &&
      (scope == 'all' || (scope == 'archive' ? n.archived : !n.archived)) &&
      (scope != 'pinned' || n.pinned) &&
      (tag.isEmpty || n.tags.contains(tag)) &&
      (types.isEmpty || types.contains(n.type)) &&
      (showDone || !n.done);
}
