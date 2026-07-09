import 'package:okf_dart/okf_dart.dart';

/// Local sync state for a note in the offline-first mirror.
enum SyncState { synced, pendingCreate, pendingUpdate, pendingDelete }

/// App-facing note model. It is a thin view over an OKF [Concept]; the OKF
/// bundle on the server remains the source of truth.
class Note {
  final String path;
  final String title;
  final String body;
  final String type;
  final List<String> tags;
  final Origin origin;
  final List<String> links;
  final List<String> attachments;
  final String source;
  final String updated;
  final int version;
  final bool done;
  final String doneAt;
  final SyncState syncState;

  const Note({
    required this.path,
    this.title = '',
    this.body = '',
    this.type = 'Note',
    this.tags = const [],
    this.origin = Origin.user,
    this.links = const [],
    this.attachments = const [],
    this.source = '',
    this.updated = '',
    this.version = 1,
    this.done = false,
    this.doneAt = '',
    this.syncState = SyncState.synced,
  });

  bool get isGenerated => origin == Origin.generated;
  bool get isPending => syncState != SyncState.synced;

  Note copyWith({
    String? title,
    String? body,
    String? type,
    List<String>? tags,
    Origin? origin,
    List<String>? links,
    List<String>? attachments,
    String? source,
    String? updated,
    int? version,
    bool? done,
    String? doneAt,
    SyncState? syncState,
  }) {
    return Note(
      path: path,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      tags: tags ?? this.tags,
      origin: origin ?? this.origin,
      links: links ?? this.links,
      attachments: attachments ?? this.attachments,
      source: source ?? this.source,
      updated: updated ?? this.updated,
      version: version ?? this.version,
      done: done ?? this.done,
      doneAt: doneAt ?? this.doneAt,
      syncState: syncState ?? this.syncState,
    );
  }

  static List<String> _attachmentsFromConcept(Concept c) {
    final raw = c.vesnai['attachments'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return const [];
  }

  Concept toConcept() {
    final vesnai = {
      'origin': origin == Origin.generated ? 'generated' : 'user',
      'links': links,
      'attachments': attachments,
      'updated': updated,
      'version': version,
    };
    if (source.isNotEmpty) {
      vesnai['source'] = source;
    }
    if (done) {
      vesnai['done'] = true;
      if (doneAt.isNotEmpty) vesnai['done_at'] = doneAt;
    }
    return Concept(
      frontmatter: {
        'type': type,
        'title': title,
        'tags': tags,
        'timestamp': updated,
        'vesnai': vesnai,
      },
      body: body,
    );
  }

  factory Note.fromConcept(String path, Concept c, {SyncState sync = SyncState.synced}) {
    final vesnai = c.vesnai;
    final rawVersion = vesnai['version'];
    final version = rawVersion is int
        ? rawVersion
        : int.tryParse(rawVersion?.toString() ?? '') ?? 1;
    final rawUpdated = vesnai['updated'] ?? c.timestamp;
    return Note(
      path: path,
      title: c.title ?? '',
      body: c.body,
      type: c.type ?? 'Note',
      tags: c.tags,
      origin: c.origin,
      links: c.links(),
      attachments: _attachmentsFromConcept(c),
      source: c.source ?? '',
      updated: rawUpdated?.toString() ?? '',
      version: version,
      done: vesnai['done'] == true,
      doneAt: vesnai['done_at']?.toString() ?? '',
      syncState: sync,
    );
  }

  factory Note.fromApi(Map<String, dynamic> json) {
    final rawVersion = json['version'];
    final version = rawVersion is int
        ? rawVersion
        : int.tryParse(rawVersion?.toString() ?? '') ?? 1;
    return Note(
      path: json['path'] as String,
      title: (json['title'] ?? '') as String,
      body: (json['body'] ?? '') as String,
      type: (json['type'] ?? 'Note') as String,
      tags: ((json['tags'] ?? const []) as List).map((e) => e.toString()).toList(),
      origin: (json['origin'] == 'generated') ? Origin.generated : Origin.user,
      links: ((json['links'] ?? const []) as List).map((e) => e.toString()).toList(),
      attachments: ((json['attachments'] ?? const []) as List)
          .map((e) => e.toString())
          .toList(),
      source: (json['source'] ?? '') as String,
      updated: (json['updated'] ?? '') as String,
      version: version,
      done: json['done'] == true,
      doneAt: (json['done_at'] ?? '') as String,
    );
  }
}
