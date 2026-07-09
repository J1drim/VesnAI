import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/chat_attachment.dart';
import '../../data/chat_store.dart';
import '../../data/voice_cache.dart';
import '../../data/shared_storage.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_outside_widgets.dart';
import '../../providers.dart';
import 'chat_message_format.dart';

/// Thrown when attachment upload fails before a turn is enqueued.
class ChatAttachmentUploadException implements Exception {
  final String message;
  ChatAttachmentUploadException(this.message);
  @override
  String toString() => message;
}

/// Thrown when a chat message could not be delivered to the server.
class ChatSendException implements Exception {
  final String message;
  ChatSendException(this.message);
  @override
  String toString() => message;
}

/// A single rendered chat message.
class ChatMessageView {
  final String id;
  final String role;
  final String content;
  final String ttsLocalPath;
  final List<ChatAttachmentMeta> attachments;
  final bool pendingImageGeneration;
  final bool imageActionFailed;
  final bool canRetryImage;
  final bool isThinking;
  final bool isSending;
  final bool isPendingSend;
  final bool turnFailed;
  final DateTime? sentAt;
  const ChatMessageView({
    required this.id,
    required this.role,
    required this.content,
    this.ttsLocalPath = '',
    this.attachments = const [],
    this.pendingImageGeneration = false,
    this.imageActionFailed = false,
    this.canRetryImage = false,
    this.isThinking = false,
    this.isSending = false,
    this.isPendingSend = false,
    this.turnFailed = false,
    this.sentAt,
  });

  bool get hasTts => ttsLocalPath.isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;

  ChatMessageView copyWith({
    String? id,
    String? role,
    String? content,
    String? ttsLocalPath,
    List<ChatAttachmentMeta>? attachments,
    bool? pendingImageGeneration,
    bool? imageActionFailed,
    bool? canRetryImage,
    bool? isThinking,
    bool? isSending,
    bool? isPendingSend,
    bool? turnFailed,
    DateTime? sentAt,
  }) =>
      ChatMessageView(
        id: id ?? this.id,
        role: role ?? this.role,
        content: content ?? this.content,
        ttsLocalPath: ttsLocalPath ?? this.ttsLocalPath,
        attachments: attachments ?? this.attachments,
        pendingImageGeneration: pendingImageGeneration ?? this.pendingImageGeneration,
        imageActionFailed: imageActionFailed ?? this.imageActionFailed,
        canRetryImage: canRetryImage ?? this.canRetryImage,
        isThinking: isThinking ?? this.isThinking,
        isSending: isSending ?? this.isSending,
        isPendingSend: isPendingSend ?? this.isPendingSend,
        turnFailed: turnFailed ?? this.turnFailed,
        sentAt: sentAt ?? this.sentAt,
      );
}

/// Chat UI state: the session list, the active session, and its messages.
class ChatState {
  final List<ChatSession> sessions;
  final String? activeId;
  final List<ChatMessageView> messages;
  final bool isCreatingChat;
  const ChatState({
    this.sessions = const [],
    this.activeId,
    this.messages = const [],
    this.isCreatingChat = false,
  });

  bool get hasThinking => messages.any(
        (m) =>
            m.isThinking ||
            (m.role == 'assistant' &&
                m.content.isEmpty &&
                m.id.isNotEmpty &&
                !m.turnFailed),
      );

  ChatState copyWith({
    List<ChatSession>? sessions,
    String? activeId,
    bool clearActive = false,
    List<ChatMessageView>? messages,
    bool? isCreatingChat,
  }) =>
      ChatState(
        sessions: sessions ?? this.sessions,
        activeId: clearActive ? null : (activeId ?? this.activeId),
        messages: messages ?? this.messages,
        isCreatingChat: isCreatingChat ?? this.isCreatingChat,
      );
}

/// Session titles default to the English "New chat" placeholder in the
/// store/server payloads; swap it for the localized string at display time.
String displaySessionTitle(AppLocalizations l, String title) =>
    (title.isEmpty || title == 'New chat') ? l.newChat : title;

/// A persisted chat conversation (server is the source of truth).
class ChatSession {
  final String id;
  final String title;
  final String created;
  final String updated;
  const ChatSession({
    required this.id,
    required this.title,
    this.created = '',
    this.updated = '',
  });

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
        id: j['id'] as String,
        title: (j['title'] ?? 'New chat') as String,
        created: (j['created'] ?? '') as String,
        updated: (j['updated'] ?? '') as String,
      );

  factory ChatSession.fromStored(StoredChatSession s) => ChatSession(
        id: s.id,
        title: s.title,
        created: s.created,
        updated: s.updated,
      );
}

/// Owns persistent multi-session chat with a local Drift cache and offline send queue.
class ChatController extends Notifier<ChatState> {
  ChatStore get _store => ref.read(chatStoreProvider);

  /// Localized strings for messages produced outside the widget tree
  /// (offline bubbles, send errors surfaced via SnackBar).
  AppLocalizations get _l10n =>
      localizationsForAppLocale(ref.read(appLocaleProvider));
  Timer? _pollTimer;
  String? _awaitingImageMessageId;
  Future<void>? _newChatInFlight;
  String? _lastWidgetChatFingerprint;
  int _outboundSends = 0;

  static const _staleAssistantMinutes = 10;

  bool get _hasOutboundWork =>
      _outboundSends > 0 || state.messages.any((m) => m.isSending);

  @override
  ChatState build() {
    ref.onDispose(_stopPolling);
    Future.microtask(_hydrateLocal);
    return const ChatState();
  }

  void _startPollingIfNeeded() {
    if (!state.hasThinking) {
      _stopPolling();
      return;
    }
    _pollTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(refreshActiveSession());
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _hydrateLocal() async {
    final stored = await _store.sessions();
    final sessions = stored.map(ChatSession.fromStored).toList();
    state = state.copyWith(sessions: sessions);
    if (state.activeId == null && sessions.isNotEmpty) {
      await switchTo(sessions.first.id);
    }
    await _publishWidgetChats();
    await refreshSessions();
    _startPollingIfNeeded();
  }

  Future<void> refreshSessions() async {
    final client = ref.read(apiClientProvider);
    if (client == null) {
      await _publishWidgetChats();
      return;
    }
    try {
      final raw = await client.listSessions();
      for (final j in raw) {
        final s = ChatSession.fromJson(j);
        await _store.upsertSession(StoredChatSession(
          id: s.id,
          title: s.title,
          created: s.created,
          updated: s.updated,
          syncState: 0,
        ));
      }
      final stored = await _store.sessions();
      state = state.copyWith(sessions: stored.map(ChatSession.fromStored).toList());
      if (state.activeId == null && stored.isNotEmpty) {
        await switchTo(stored.first.id);
      }
      await _publishWidgetChats();
    } catch (_) {
      await _publishWidgetChats();
    }
  }

  /// Mirror local chat sessions to the home-screen widget (no server required).
  Future<void> publishWidgetFromLocalStore() async {
    final stored = await _store.sessions();
    state = state.copyWith(sessions: stored.map(ChatSession.fromStored).toList());
    await _publishWidgetChats();
  }

  Future<void> newChat() {
    if (_newChatInFlight != null) return _newChatInFlight!;
    _newChatInFlight = _newChatImpl().whenComplete(() {
      _newChatInFlight = null;
    });
    return _newChatInFlight!;
  }

  Future<void> _newChatImpl() async {
    state = state.copyWith(isCreatingChat: true, messages: const []);
    try {
      final client = ref.read(apiClientProvider);
      if (client != null) {
        try {
          final created = await client.createSession();
          final session = ChatSession.fromJson(created);
          await _store.upsertSession(StoredChatSession(
            id: session.id,
            title: session.title,
            created: session.created,
            updated: session.updated,
          ));
          state = state.copyWith(
            sessions: [session, ...state.sessions],
            activeId: session.id,
            messages: const [],
          );
          unawaited(
            _publishWidgetChats().catchError((Object _, StackTrace __) {}),
          );
          return;
        } catch (_) {}
      }
      final local = await _store.createSession();
      final session = ChatSession.fromStored(local);
      state = state.copyWith(
        sessions: [session, ...state.sessions],
        activeId: session.id,
        messages: const [],
      );
      unawaited(
        _publishWidgetChats().catchError((Object _, StackTrace __) {}),
      );
    } finally {
      state = state.copyWith(isCreatingChat: false);
    }
  }

  List<ChatAttachmentMeta> _attachmentsFromJson(List raw, String sessionId) => raw
      .map((e) => ChatAttachmentMeta.fromJson(e as Map<String, dynamic>, sessionId: sessionId))
      .toList();

  StoredChatMessage _storedFromApiMap(Map<String, dynamic> map, String sessionId) =>
      StoredChatMessage(
        id: map['id'] as String? ?? '',
        sessionId: sessionId,
        role: map['role'] as String,
        content: map['content'] as String,
        ts: map['ts'] as String? ?? '',
        attachments: _attachmentsFromJson((map['attachments'] ?? const []) as List, sessionId),
        metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? const {}),
      );

  ({bool failed, bool canRetry, bool pending}) _imageActionState(
    Map<String, dynamic> metadata,
  ) {
    final pending = (metadata['pending_actions'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    for (final action in pending) {
      if (action['kind'] != 'generate_image') continue;
      final status = action['status'] as String? ?? '';
      if (status == 'failed') {
        return (failed: true, canRetry: true, pending: false);
      }
      if (status == 'queued') {
        return (failed: false, canRetry: false, pending: true);
      }
    }
    return (failed: false, canRetry: false, pending: false);
  }

  bool _isStaleAssistant(StoredChatMessage m) {
    if (m.role != 'assistant' || m.content.isNotEmpty) return false;
    final ts = DateTime.tryParse(m.ts);
    if (ts == null) return false;
    return DateTime.now().difference(ts.toLocal()) >
        const Duration(minutes: _staleAssistantMinutes);
  }

  ChatMessageView _viewFromStored(StoredChatMessage m) {
    final failed = m.metadata['turn_failed'] == true;
    final stale = _isStaleAssistant(m);
    final turnFailed = failed || stale;
    final thinking =
        m.role == 'assistant' && m.content.isEmpty && m.id.isNotEmpty && !turnFailed;
    final displayContent =
        stale && m.content.isEmpty ? _l10n.replyDidNotFinish : m.content;
    final ttsPath = ttsPathMatchesContent(m.ttsAudioPath, m.content)
        ? m.ttsAudioPath
        : '';
    final imageState = _imageActionState(m.metadata);
    return ChatMessageView(
      id: m.id,
      role: m.role,
      content: displayContent,
      ttsLocalPath: ttsPath,
      attachments: m.attachments,
      pendingImageGeneration: imageState.pending,
      imageActionFailed: imageState.failed,
      canRetryImage: imageState.canRetry,
      isThinking: thinking,
      isSending: m.isSending,
      isPendingSend: m.isPendingSend,
      turnFailed: turnFailed,
      sentAt: parseChatMessageSentAt(m.ts),
    );
  }

  Future<void> switchTo(String id, {bool forceRefresh = false}) async {
    final prevMessages =
        state.activeId == id ? List<ChatMessageView>.from(state.messages) : null;
    if (!forceRefresh) {
      final stored = await _store.messages(id);
      if (stored.isNotEmpty) {
        state = state.copyWith(
          activeId: id,
          messages: _mapMessages(stored),
        );
        _startPollingIfNeeded();
        if (prevMessages != null) {
          _maybeSyncNotesAfterTurn(prevMessages, state.messages);
        }
        return;
      }
    }
    final client = ref.read(apiClientProvider);
    if (client == null) {
      final stored = await _store.messages(id);
      state = state.copyWith(
        activeId: id,
        messages: _mapMessages(stored),
      );
      return;
    }
    try {
      final detail = await client.getSession(id);
      final storedMessages = ((detail['messages'] ?? const []) as List)
          .map((m) => _storedFromApiMap(m as Map<String, dynamic>, id))
          .toList();
      if (storedMessages.isEmpty) {
        final local = await _store.messages(id);
        if (local.isNotEmpty) {
          state = state.copyWith(
            activeId: id,
            messages: _mapMessages(local),
          );
          _startPollingIfNeeded();
          return;
        }
      }
      await _store.replaceSessionMessages(id, storedMessages);
      final merged = await _store.messages(id);
      state = state.copyWith(
        activeId: id,
        messages: _mapMessages(merged),
      );
    } catch (_) {
      final stored = await _store.messages(id);
      state = state.copyWith(
        activeId: id,
        messages: stored.isNotEmpty
            ? _mapMessages(stored)
            : state.activeId == id
                ? state.messages
                : const [],
      );
    }
    _startPollingIfNeeded();
    if (prevMessages != null && state.activeId == id) {
      _maybeSyncNotesAfterTurn(prevMessages, state.messages);
    }
  }

  void markAwaitingImage(String? messageId) {
    _awaitingImageMessageId = messageId;
  }

  void clearAwaitingImage([String? messageId]) {
    if (messageId != null && _awaitingImageMessageId != messageId) {
      return;
    }
    if (_awaitingImageMessageId == null) {
      return;
    }
    final awaitingId = _awaitingImageMessageId;
    _awaitingImageMessageId = null;
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id == awaitingId && m.pendingImageGeneration)
            m.copyWith(pendingImageGeneration: false)
          else
            m,
      ],
    );
  }

  void markImageActionFailed(String? messageId) {
    if (messageId == null) return;
    _awaitingImageMessageId = null;
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id == messageId)
            m.copyWith(
              pendingImageGeneration: false,
              imageActionFailed: true,
              canRetryImage: true,
            )
          else
            m,
      ],
    );
  }

  Future<void> retryImageGeneration(String messageId) async {
    final sessionId = state.activeId;
    final client = ref.read(apiClientProvider);
    if (sessionId == null || client == null) return;
    try {
      await client.retryChatAction(sessionId, messageId);
      _awaitingImageMessageId = messageId;
      state = state.copyWith(
        messages: [
          for (final m in state.messages)
            if (m.id == messageId)
              m.copyWith(
                pendingImageGeneration: true,
                imageActionFailed: false,
                canRetryImage: false,
              )
            else
              m,
        ],
      );
    } catch (_) {}
  }

  void _maybeSyncNotesAfterTurn(
    List<ChatMessageView> before,
    List<ChatMessageView> after,
  ) {
    final beforeById = {for (final m in before) m.id: m};
    for (final msg in after) {
      if (msg.role != 'assistant') continue;
      final prev = beforeById[msg.id];
      if (prev == null) continue;
      final contentReady =
          prev.content.isEmpty && msg.content.isNotEmpty && !msg.isThinking;
      final attachmentsAdded = prev.attachments.length < msg.attachments.length;
      if (contentReady || attachmentsAdded) {
        unawaited(ref.read(notesProvider.notifier).sync());
        return;
      }
    }
  }

  List<ChatMessageView> _mapMessages(List<StoredChatMessage> stored) {
    return stored.map((m) {
      var view = _viewFromStored(m);
      if (_awaitingImageMessageId != null &&
          view.id == _awaitingImageMessageId &&
          view.role == 'assistant' &&
          !view.attachments.any((a) => a.isImage)) {
        view = view.copyWith(pendingImageGeneration: true);
      } else if (_awaitingImageMessageId != null &&
          view.id == _awaitingImageMessageId &&
          view.attachments.any((a) => a.isImage)) {
        _awaitingImageMessageId = null;
      }
      return view;
    }).toList();
  }

  Future<void> refreshActiveSession() async {
    if (_hasOutboundWork) return;
    final id = state.activeId;
    if (id != null) await switchTo(id, forceRefresh: true);
  }

  Future<void> deleteSession(String id) async {
    final voiceCache = ref.read(voiceCacheProvider);
    final msgs = await _store.messagesForSession(id);
    await voiceCache.deleteForMessages(msgs.map((m) => m.id));
    final client = ref.read(apiClientProvider);
    if (client != null && !id.startsWith('local-')) {
      try {
        await client.deleteSession(id);
      } catch (_) {}
    }
    await _store.deleteSession(id);
    final remaining = state.sessions.where((s) => s.id != id).toList();
    if (state.activeId == id) {
      state = state.copyWith(
        sessions: remaining,
        clearActive: true,
        messages: const [],
      );
      if (remaining.isNotEmpty) await switchTo(remaining.first.id);
    } else {
      state = state.copyWith(sessions: remaining);
    }
    await _publishWidgetChats();
  }

  void _appendLocal(
    String id,
    String role,
    String content, {
    String ttsLocalPath = '',
    List<ChatAttachmentMeta> attachments = const [],
    bool pendingImageGeneration = false,
    bool isThinking = false,
    bool isSending = false,
    bool isPendingSend = false,
  }) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessageView(
          id: id,
          role: role,
          content: content,
          ttsLocalPath: ttsLocalPath,
          attachments: attachments,
          pendingImageGeneration: pendingImageGeneration,
          isThinking: isThinking,
          isSending: isSending,
          isPendingSend: isPendingSend,
          sentAt: DateTime.now(),
        ),
      ],
    );
    _startPollingIfNeeded();
  }

  void _updateLocalMessage(
    String id, {
    String? newId,
    bool? isSending,
    bool? isPendingSend,
    List<ChatAttachmentMeta>? attachments,
  }) {
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id == id)
            m.copyWith(
              id: newId ?? m.id,
              isSending: isSending,
              isPendingSend: isPendingSend,
              attachments: attachments ?? m.attachments,
            )
          else
            m,
      ],
    );
  }

  void _markUserSending(String id) {
    _updateLocalMessage(id, isSending: true, isPendingSend: false);
  }

  void _markUserPendingSend(String id) {
    _updateLocalMessage(id, isSending: false, isPendingSend: true);
  }

  void _markUserSent(String id, {String? newId}) {
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id == id)
            m.copyWith(
              id: newId ?? m.id,
              isSending: false,
              isPendingSend: false,
            )
          else
            m,
      ],
    );
  }

  void _updateMessageTts(String id, String path) {
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id == id)
            m.copyWith(ttsLocalPath: path)
          else
            m,
      ],
    );
  }

  Future<String?> _ensureSession() async {
    if (_newChatInFlight != null) {
      await _newChatInFlight;
      return state.activeId;
    }
    if (state.activeId != null) return state.activeId;
    await newChat();
    return state.activeId;
  }

  Future<String> _ensureServerSession(String sessionId) async {
    final client = ref.read(apiClientProvider);
    if (client == null) return sessionId;

    if (sessionId.startsWith('local-')) {
      return _promoteLocalSession(sessionId);
    }
    try {
      await client.getSession(sessionId);
      return sessionId;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return _promoteLocalSession(sessionId);
      }
      rethrow;
    }
  }

  Future<String> _promoteLocalSession(String sessionId) async {
    final client = ref.read(apiClientProvider)!;
    final created = await client.createSession();
    final newId = created['id'] as String;
    await _store.remapSessionId(sessionId, newId);
    final session = ChatSession.fromJson(created);
    await _store.upsertSession(StoredChatSession(
      id: session.id,
      title: session.title,
      created: session.created,
      updated: session.updated,
    ));
    state = state.copyWith(
      activeId: newId,
      sessions: [
        session,
        ...state.sessions.where((s) => s.id != sessionId),
      ],
    );
    return newId;
  }

  Future<List<ChatAttachmentMeta>> _cachePendingAttachments(
    String sessionId,
    List<PendingChatAttachment> attachments,
  ) async {
    if (attachments.isEmpty) return const [];
    final cache = ref.read(chatAttachmentCacheProvider);
    final local = <ChatAttachmentMeta>[];
    for (final a in attachments) {
      final pendingPath = 'pending-${DateTime.now().microsecondsSinceEpoch}-${a.filename}';
      await cache.write(sessionId, pendingPath, Uint8List.fromList(a.bytes));
      local.add(ChatAttachmentMeta(
        path: pendingPath,
        kind: a.kind,
        filename: a.filename,
        sessionId: sessionId,
      ));
    }
    return local;
  }

  void _updateLocalMessageAttachments(String id, List<ChatAttachmentMeta> attachments) {
    _updateLocalMessage(id, attachments: attachments);
  }

  Future<void> _rehomeCachedAttachments(
    String fromSessionId,
    String toSessionId,
    List<ChatAttachmentMeta> attachments,
  ) async {
    if (fromSessionId == toSessionId || attachments.isEmpty) return;
    final cache = ref.read(chatAttachmentCacheProvider);
    for (final a in attachments) {
      final bytes = await cache.readBytes(fromSessionId, a.path);
      if (bytes != null) {
        await cache.write(toSessionId, a.path, bytes);
      }
    }
  }

  Future<List<PendingChatAttachment>> _pendingAttachmentsFromStored(
    StoredChatMessage msg,
  ) async {
    if (msg.attachments.isEmpty) return const [];
    final cache = ref.read(chatAttachmentCacheProvider);
    final out = <PendingChatAttachment>[];
    for (final a in msg.attachments) {
      final bytes = await cache.readBytes(msg.sessionId, a.path);
      if (bytes == null) continue;
      out.add(PendingChatAttachment(
        filename: a.filename,
        bytes: bytes,
        kind: a.kind,
      ));
    }
    return out;
  }

  bool _attachmentsNeedUpload(List<ChatAttachmentMeta> attachments) {
    return attachments.any((a) => a.path.startsWith('pending-'));
  }

  Future<void> _deliverUserMessage({
    required String messageId,
    required String content,
    required String sessionId,
    required List<ChatAttachmentMeta> localAttachments,
    required List<PendingChatAttachment> rawAttachments,
    String? assistantLanguage,
  }) async {
    final client = ref.read(apiClientProvider);
    if (client == null) {
      await _store.updateMessageSync(messageId, syncState: 1);
      _markUserPendingSend(messageId);
      return;
    }

    var activeSessionId = sessionId;
    _outboundSends++;
    try {
      if (rawAttachments.isNotEmpty || activeSessionId.startsWith('local-')) {
        final priorSessionId = activeSessionId;
        activeSessionId = await _ensureServerSession(activeSessionId);
        if (priorSessionId != activeSessionId) {
          await _rehomeCachedAttachments(
            priorSessionId,
            activeSessionId,
            localAttachments,
          );
        }
      }

      var uploaded = localAttachments;
      if (rawAttachments.isNotEmpty && _attachmentsNeedUpload(localAttachments)) {
        uploaded = await _uploadAttachments(activeSessionId, rawAttachments);
        await _store.updateMessageAttachments(messageId, uploaded);
        _updateLocalMessage(messageId, attachments: uploaded);
        final cache = ref.read(chatAttachmentCacheProvider);
        for (var i = 0; i < uploaded.length; i++) {
          final pendingPath = localAttachments[i].path;
          final bytes = await cache.readBytes(activeSessionId, pendingPath);
          if (bytes != null) {
            await cache.write(activeSessionId, uploaded[i].path, bytes);
          }
        }
      }

      final locationContext = await _resolveLocationContext();
      final accepted = await client.enqueueChatTurn(
        content,
        assistantLanguage: assistantLanguage,
        sessionId: activeSessionId,
        attachmentRefs: uploaded.map((a) => a.toJson()).toList(),
        locationContext: locationContext,
      );

      final serverUserId = accepted.userMessageId;
      await _store.updateMessageSync(messageId, syncState: 0);
      if (serverUserId != null &&
          serverUserId.isNotEmpty &&
          serverUserId != messageId) {
        await _store.remapMessageId(messageId, serverUserId);
        _markUserSent(messageId, newId: serverUserId);
      } else {
        _markUserSent(messageId);
      }

      final assistantId = accepted.assistantMessageId ?? '';
      if (assistantId.isNotEmpty &&
          !state.messages.any((m) => m.id == assistantId)) {
        await _store.appendMessage(
          sessionId: activeSessionId,
          role: 'assistant',
          content: '',
          id: assistantId,
        );
        _appendLocal(assistantId, 'assistant', '', isThinking: true);
      }
      unawaited(
        refreshSessions().catchError((Object _, StackTrace __) {}),
      );
    } on ChatAttachmentUploadException {
      await _store.updateMessageSync(messageId, syncState: 1);
      _markUserPendingSend(messageId);
      rethrow;
    } catch (e) {
      await _store.updateMessageSync(messageId, syncState: 1);
      _markUserPendingSend(messageId);
      if (e is ChatSendException) rethrow;
      throw ChatSendException(
        e is ApiException
            ? _l10n.couldNotSendTapRetryStatus(e.statusCode)
            : _l10n.couldNotSendTapRetry,
      );
    } finally {
      _outboundSends--;
    }
  }

  Future<List<ChatAttachmentMeta>> _uploadAttachments(
    String sessionId,
    List<PendingChatAttachment> attachments,
  ) async {
    final client = ref.read(apiClientProvider);
    if (client == null) {
      throw ChatAttachmentUploadException(_l10n.connectToSendAttachments);
    }
    final cache = ref.read(chatAttachmentCacheProvider);
    final uploaded = <ChatAttachmentMeta>[];
    for (final a in attachments) {
      try {
        final meta = await client.uploadChatAttachment(
          sessionId,
          a.filename,
          Uint8List.fromList(a.bytes),
          kind: a.kind,
        );
        final attachment = ChatAttachmentMeta.fromJson(meta, sessionId: sessionId);
        await cache.write(sessionId, attachment.path, Uint8List.fromList(a.bytes));
        uploaded.add(attachment);
      } catch (e) {
        throw ChatAttachmentUploadException(
          chatAttachmentUploadErrorMessage(e, a.filename, _l10n),
        );
      }
    }
    return uploaded;
  }

  /// Optional GPS context for this turn when the user enabled sharing in Settings.
  Future<Map<String, dynamic>?> _resolveLocationContext() async {
    final shareEnabled = ref.read(shareLocationWithChatProvider);
    if (!shareEnabled) return null;
    final saved = ref.read(savedChatLocationProvider);
    final resolved = await ref.read(chatLocationServiceProvider).resolveForChat(
          shareEnabled: true,
          saved: saved,
        );
    if (resolved != null && resolved != saved) {
      await ref.read(savedChatLocationProvider.notifier).save(resolved);
    }
    return resolved?.toApiJson();
  }

  Future<List<dynamic>> send(
    String message, {
    String? assistantLanguage,
    List<PendingChatAttachment> attachments = const [],
    void Function()? onBubbleVisible,
  }) async {
    final sessionId = await _ensureSession();
    if (sessionId == null) {
      _appendLocal('', 'user', message, attachments: attachments.map((a) =>
          ChatAttachmentMeta(path: '', kind: a.kind, filename: a.filename)).toList());
      _appendLocal('', 'assistant', _l10n.connectToChat);
      onBubbleVisible?.call();
      return const [];
    }

    final client = ref.read(apiClientProvider);
    var activeSessionId = sessionId;

    final localAttachments =
        await _cachePendingAttachments(activeSessionId, attachments);

    final userMsg = await _store.appendMessage(
      sessionId: activeSessionId,
      role: 'user',
      content: message,
      syncState: client == null ? 1 : 2,
      attachments: localAttachments,
    );
    _appendLocal(
      userMsg.id,
      'user',
      message,
      attachments: localAttachments,
      isSending: client != null,
      isPendingSend: client == null,
    );
    onBubbleVisible?.call();

    if (client == null) {
      return const [];
    }

    await _deliverUserMessage(
      messageId: userMsg.id,
      content: message,
      sessionId: activeSessionId,
      localAttachments: localAttachments,
      rawAttachments: attachments,
      assistantLanguage: assistantLanguage,
    );
    return const [];
  }

  Future<void> retrySend(String messageId, {String? assistantLanguage}) async {
    final stored = await _store.messageById(messageId);
    if (stored == null || stored.role != 'user' || !stored.isPendingSend) {
      return;
    }
    await _store.updateMessageSync(messageId, syncState: 2);
    _markUserSending(messageId);
    final rawAttachments = await _pendingAttachmentsFromStored(stored);
    await _deliverUserMessage(
      messageId: messageId,
      content: stored.content,
      sessionId: stored.sessionId,
      localAttachments: stored.attachments,
      rawAttachments: rawAttachments,
      assistantLanguage: assistantLanguage,
    );
  }

  Future<void> cacheTtsForMessage(String messageId, String path) async {
    await _store.updateTtsPath(messageId, path);
    _updateMessageTts(messageId, path);
  }

  Future<void> flushPending() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    final pending = await _store.pendingUserMessages();
    for (final msg in pending) {
      try {
        var sessionId = msg.sessionId;
        if (sessionId.startsWith('local-')) {
          final created = await client.createSession();
          sessionId = created['id'] as String;
          await _store.remapSessionId(msg.sessionId, sessionId);
        }
        final locationContext = await _resolveLocationContext();
        final accepted = await client.enqueueChatTurn(
          msg.content,
          sessionId: sessionId,
          attachmentRefs: msg.attachments.map((a) => a.toJson()).toList(),
          locationContext: locationContext,
        );
        await _store.updateMessageSync(msg.id, syncState: 0);
        final assistantId = accepted.assistantMessageId;
        if (assistantId != null && assistantId.isNotEmpty) {
          await _store.appendMessage(
            sessionId: sessionId,
            role: 'assistant',
            content: '',
            id: assistantId,
          );
        }
      } catch (_) {
        break;
      }
    }
    await refreshSessions();
    if (state.activeId != null) await switchTo(state.activeId!, forceRefresh: true);
  }

  Future<void> _publishWidgetChats() async {
    final recents = state.sessions
        .take(kWidgetRecentsLimit)
        .map((s) => WidgetChat(id: s.id, title: s.title, updated: s.updated))
        .toList();
    final fingerprint = recents.map((c) => '${c.id}|${c.title}|${c.updated}').join(';');
    if (fingerprint == _lastWidgetChatFingerprint) return;
    _lastWidgetChatFingerprint = fingerprint;
    await ref.read(notesProvider.notifier).publishChatRecents(recents);
  }
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);
