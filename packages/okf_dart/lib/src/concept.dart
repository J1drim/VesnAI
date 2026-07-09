// OKF concept model (Dart mirror of the Python model).

const reservedFilenames = {'index.md', 'log.md'};

const recommendedOrder = [
  'type',
  'title',
  'description',
  'resource',
  'tags',
  'timestamp',
];

final _markdownLink = RegExp(r'\[[^\]]*\]\(([^)]+)\)');

enum Origin { user, generated }

class Concept {
  Map<String, dynamic> frontmatter;
  String body;

  Concept({Map<String, dynamic>? frontmatter, this.body = ''})
      : frontmatter = frontmatter ?? <String, dynamic>{};

  String? get type => frontmatter['type']?.toString();
  String? get title => frontmatter['title']?.toString();
  String? get description => frontmatter['description']?.toString();
  String? get timestamp => frontmatter['timestamp']?.toString();

  List<String> get tags {
    final value = frontmatter['tags'];
    if (value == null) return const [];
    if (value is String) return [value];
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }

  Map<String, dynamic> get vesnai {
    final ns = frontmatter['vesnai'];
    if (ns is Map) return ns.cast<String, dynamic>();
    final created = <String, dynamic>{};
    frontmatter['vesnai'] = created;
    return created;
  }

  Origin get origin {
    final raw = vesnai['origin']?.toString() ?? 'user';
    return raw == 'generated' ? Origin.generated : Origin.user;
  }

  bool get isGenerated => origin == Origin.generated;

  String? get noteId => vesnai['id']?.toString();
  String? get source => vesnai['source']?.toString();

  List<String> explicitLinks() {
    final value = vesnai['links'];
    if (value == null) return const [];
    if (value is String) return [value];
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }

  List<String> bodyLinks() =>
      _markdownLink.allMatches(body).map((m) => m.group(1)!).toList();

  List<String> links() {
    final out = <String>[...explicitLinks()];
    for (final href in bodyLinks()) {
      if (!out.contains(href)) out.add(href);
    }
    return out;
  }
}
