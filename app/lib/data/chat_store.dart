import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import 'chat_attachment.dart';
import 'drift/database.dart';
import 'voice_cache.dart';

/// Local persistence for chat sessions and messages (offline cache + send queue).
class ChatStore {
  final VesnaiDatabase db;
  static final _rand = Random();

  ChatStore([VesnaiDatabase? database]) : db = database ?? VesnaiDatabase();

  static String _newId({String prefix = ''}) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 30)}';

  Future<List<StoredChatSession>> sessions() async {
    final rows = await (db.select(db.chatSessionRows)
          ..orderBy([(t) => OrderingTerm.desc(t.updated)]))
        .get();
    return rows
        .map((r) => StoredChatSession(
              id: r.id,
              title: r.title,
              created: r.created,
              updated: r.updated,
              syncState: r.syncState,
            ))
        .toList();
  }

  Future<List<StoredChatMessage>> messages(String sessionId) async {
    final rows = await (db.select(db.chatMessageRows)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.ts)]))
        .get();
    return rows.map(_messageFromRow).toList();
  }

  Future<StoredChatSession> createSession({String title = 'New chat'}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = _newId(prefix: 'local-');
    await db.into(db.chatSessionRows).insert(
          ChatSessionRowsCompanion.insert(
            id: id,
            title: Value(title),
            created: Value(now),
            updated: Value(now),
            syncState: const Value(1),
          ),
        );
    return StoredChatSession(
      id: id,
      title: title,
      created: now,
      updated: now,
      syncState: 1,
    );
  }

  Future<void> upsertSession(StoredChatSession s) async {
    await db.into(db.chatSessionRows).insertOnConflictUpdate(
          ChatSessionRowsCompanion.insert(
            id: s.id,
            title: Value(s.title),
            created: Value(s.created),
            updated: Value(s.updated),
            syncState: Value(s.syncState),
          ),
        );
  }

  Future<void> deleteSession(String id) async {
    await (db.delete(db.chatMessageRows)..where((t) => t.sessionId.equals(id))).go();
    await (db.delete(db.chatSessionRows)..where((t) => t.id.equals(id))).go();
  }

  Future<StoredChatMessage> appendMessage({
    required String sessionId,
    required String role,
    required String content,
    int syncState = 0,
    List<ChatAttachmentMeta> attachments = const [],
    String? id,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final msgId = id ?? _newId();
    await db.into(db.chatMessageRows).insert(
          ChatMessageRowsCompanion.insert(
            id: msgId,
            sessionId: sessionId,
            role: role,
            content: Value(content),
            ts: Value(now),
            syncState: Value(syncState),
            attachmentsJson: Value(jsonEncode(attachments.map((a) => a.toJson()).toList())),
          ),
        );
    await (db.update(db.chatSessionRows)..where((t) => t.id.equals(sessionId)))
        .write(ChatSessionRowsCompanion(updated: Value(now)));
    return StoredChatMessage(
      id: msgId,
      sessionId: sessionId,
      role: role,
      content: content,
      ts: now,
      syncState: syncState,
      attachments: attachments,
    );
  }

  Future<void> replaceSessionMessages(
    String sessionId,
    List<StoredChatMessage> serverMessages,
  ) async {
    final existing = await messages(sessionId);
    final existingById = {for (final m in existing) m.id: m};
    final serverIds = {for (final m in serverMessages) m.id};
    final unsyncedLocal = existing
        .where((m) => m.syncState != 0 && !serverIds.contains(m.id))
        .toList();
    final merged = <StoredChatMessage>[
      ...serverMessages.map(
        (m) => m.copyWith(syncState: 0, sessionId: sessionId),
      ),
      ...unsyncedLocal,
    ]..sort((a, b) => a.ts.compareTo(b.ts));

    await (db.delete(db.chatMessageRows)..where((t) => t.sessionId.equals(sessionId))).go();
    for (final m in merged) {
      final prior = existingById[m.id];
      var ttsPath = m.ttsAudioPath;
      if (prior != null &&
          prior.ttsAudioPath.isNotEmpty &&
          ttsPathMatchesContent(prior.ttsAudioPath, m.content)) {
        ttsPath = prior.ttsAudioPath;
      } else if (ttsPath.isEmpty) {
        ttsPath = '';
      }
      await db.into(db.chatMessageRows).insert(
            ChatMessageRowsCompanion.insert(
              id: m.id.isNotEmpty ? m.id : _newId(),
              sessionId: sessionId,
              role: m.role,
              content: Value(m.content),
              ts: Value(m.ts),
              syncState: Value(m.syncState),
              ttsAudioPath: Value(ttsPath),
              attachmentsJson: Value(
                jsonEncode(m.attachments.map((a) => a.toJson()).toList()),
              ),
            ),
          );
    }
  }

  Future<StoredChatMessage?> messageById(String id) async {
    final rows = await (db.select(db.chatMessageRows)..where((t) => t.id.equals(id))).get();
    if (rows.isEmpty) return null;
    return _messageFromRow(rows.first);
  }

  Future<void> remapMessageId(String oldId, String newId) async {
    if (oldId == newId || oldId.isEmpty || newId.isEmpty) return;
    final rows = await (db.select(db.chatMessageRows)..where((t) => t.id.equals(oldId))).get();
    if (rows.isEmpty) return;
    final row = rows.first;
    await (db.delete(db.chatMessageRows)..where((t) => t.id.equals(oldId))).go();
    await db.into(db.chatMessageRows).insert(
          ChatMessageRowsCompanion.insert(
            id: newId,
            sessionId: row.sessionId,
            role: row.role,
            content: Value(row.content),
            ts: Value(row.ts),
            syncState: Value(row.syncState),
            ttsAudioPath: Value(row.ttsAudioPath),
            attachmentsJson: Value(row.attachmentsJson),
          ),
        );
  }

  Future<void> updateTtsPath(String id, String path) async {
    await (db.update(db.chatMessageRows)..where((t) => t.id.equals(id))).write(
          ChatMessageRowsCompanion(ttsAudioPath: Value(path)),
        );
  }

  Future<void> updateMessageSync(String id, {required int syncState, String? content}) async {
    await (db.update(db.chatMessageRows)..where((t) => t.id.equals(id))).write(
          ChatMessageRowsCompanion(
            syncState: Value(syncState),
            content: content == null ? const Value.absent() : Value(content),
          ),
        );
  }

  Future<void> updateMessageAttachments(
    String id,
    List<ChatAttachmentMeta> attachments,
  ) async {
    await (db.update(db.chatMessageRows)..where((t) => t.id.equals(id))).write(
          ChatMessageRowsCompanion(
            attachmentsJson: Value(
              jsonEncode(attachments.map((a) => a.toJson()).toList()),
            ),
          ),
        );
  }

  Future<List<StoredChatMessage>> pendingUserMessages() async {
    final rows = await (db.select(db.chatMessageRows)
          ..where((t) => t.syncState.equals(1) & t.role.equals('user')))
        .get();
    return rows.map(_messageFromRow).toList();
  }

  Future<List<StoredChatMessage>> messagesForSession(String sessionId) async {
    final rows = await (db.select(db.chatMessageRows)
          ..where((t) => t.sessionId.equals(sessionId)))
        .get();
    return rows.map(_messageFromRow).toList();
  }

  Future<void> remapSessionId(String oldId, String newId) async {
    await (db.update(db.chatSessionRows)..where((t) => t.id.equals(oldId)))
        .write(ChatSessionRowsCompanion(id: Value(newId), syncState: const Value(0)));
    await (db.update(db.chatMessageRows)..where((t) => t.sessionId.equals(oldId)))
        .write(ChatMessageRowsCompanion(sessionId: Value(newId)));
  }

  StoredChatMessage _messageFromRow(ChatMessageRow r) {
    List<ChatAttachmentMeta> attachments = const [];
    try {
      final raw = jsonDecode(r.attachmentsJson) as List;
      attachments = raw
          .map((e) => ChatAttachmentMeta.fromJson(e as Map<String, dynamic>,
              sessionId: r.sessionId))
          .toList();
    } catch (_) {}
    return StoredChatMessage(
      id: r.id,
      sessionId: r.sessionId,
      role: r.role,
      content: r.content,
      ts: r.ts,
      syncState: r.syncState,
      ttsAudioPath: r.ttsAudioPath,
      attachments: attachments,
    );
  }
}

class StoredChatSession {
  final String id;
  final String title;
  final String created;
  final String updated;
  final int syncState;
  const StoredChatSession({
    required this.id,
    required this.title,
    required this.created,
    required this.updated,
    this.syncState = 0,
  });

  bool get isLocal => id.startsWith('local-');
  bool get isPending => syncState != 0;
}

class StoredChatMessage {
  final String id;
  final String sessionId;
  final String role;
  final String content;
  final String ts;
  final int syncState;
  final String ttsAudioPath;
  final List<ChatAttachmentMeta> attachments;
  final Map<String, dynamic> metadata;
  const StoredChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.ts,
    this.syncState = 0,
    this.ttsAudioPath = '',
    this.attachments = const [],
    this.metadata = const {},
  });

  bool get isSending => syncState == 2 && role == 'user';
  bool get isPendingSend => syncState == 1 && role == 'user';
  bool get hasTts => ttsAudioPath.isNotEmpty;

  StoredChatMessage copyWith({
    String? id,
    String? sessionId,
    String? role,
    String? content,
    String? ts,
    int? syncState,
    String? ttsAudioPath,
    List<ChatAttachmentMeta>? attachments,
    Map<String, dynamic>? metadata,
  }) =>
      StoredChatMessage(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        role: role ?? this.role,
        content: content ?? this.content,
        ts: ts ?? this.ts,
        syncState: syncState ?? this.syncState,
        ttsAudioPath: ttsAudioPath ?? this.ttsAudioPath,
        attachments: attachments ?? this.attachments,
        metadata: metadata ?? this.metadata,
      );
}
