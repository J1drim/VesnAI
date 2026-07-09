import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../models/note.dart';

/// User-facing hint when a chat attachment upload fails mid-transfer.
String chatAttachmentUploadErrorMessage(
    Object error, String filename, AppLocalizations l) {
  return _attachmentUploadErrorMessage(error, filename, l);
}

/// User-facing hint when a note attachment upload fails mid-transfer.
String noteAttachmentUploadErrorMessage(
    Object error, String filename, AppLocalizations l) {
  return _attachmentUploadErrorMessage(error, filename, l);
}

String _attachmentUploadErrorMessage(
    Object error, String filename, AppLocalizations l) {
  final detail = error.toString();
  if (error is ApiException) {
    if (error.statusCode == 404) return l.uploadSessionNotFound;
    if (error.statusCode == 413) return l.uploadTooLarge;
  }
  if (detail.contains('Connection closed') ||
      detail.contains('SocketException') ||
      detail.contains('TimeoutException')) {
    return l.uploadConnectionDropped(filename);
  }
  return l.uploadFailed(filename, '$error');
}

/// Parse FastAPI ``{"detail": "..."}`` error bodies when present.
String? fastApiErrorDetail(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final detail = decoded['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty) {
      return detail.map((e) => e.toString()).join('; ');
    }
  } catch (_) {}
  return null;
}

/// User-facing hint when server TTS fails (503 voice config, 502 sidecar, …).
String ttsErrorMessage(Object error, AppLocalizations l) {
  if (error is ApiException) {
    final detail = fastApiErrorDetail(error.body) ?? '';
    final lower = detail.toLowerCase();
    if (error.statusCode == 503) {
      if (lower.contains('api key')) return l.ttsApiKeyRejected;
      if (lower.contains('no voice') ||
          lower.contains('not registered') ||
          lower.contains('not configured') ||
          lower.contains('missing')) {
        return l.ttsRegisterFirst;
      }
    }
    if (detail.isNotEmpty) return l.ttsVoiceServiceError(detail);
  }
  return l.ttsFailed;
}

/// Thrown when a pairing code is rejected (invalid/expired) by the server.
class PairingException implements Exception {
  final String message;
  PairingException(this.message);
  @override
  String toString() => 'PairingException: $message';
}

/// User-facing hint when pairing fails before an HTTP response is received.
String pairingConnectionErrorMessage(Object error, AppLocalizations l) {
  if (error is HandshakeException) return l.pairingErrorTls;
  if (error is SocketException) return l.pairingErrorServerUnreachable;
  return l.unreachableServer;
}

/// Redeem a pairing code for a long-lived per-device bearer token.
/// Usable before a [VesnaiApiClient] exists; pass the shared [httpClientProvider] client.
Future<({String token, String deviceId})> pairWithServer(
  Uri baseUrl,
  String code,
  String deviceName, {
  required http.Client client,
}) async {
  final resp = await client.post(
    baseUrl.resolve('/v1/auth/pair'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'code': code, 'device_name': deviceName}),
  );
  if (resp.statusCode == 401) {
    throw PairingException('Invalid or expired pairing code.');
  }
  if (resp.statusCode >= 400) {
    throw ApiException(resp.statusCode, resp.body);
  }
  final j = jsonDecode(resp.body) as Map<String, dynamic>;
  return (token: j['token'] as String, deviceId: j['device_id'] as String);
}

/// Thin client for the VesnAI server API. The [http.Client] is injectable so it
/// can be faked in tests (no real network).
class VesnaiApiClient {
  final Uri baseUrl;
  final String token;
  final http.Client _client;

  VesnaiApiClient({
    required this.baseUrl,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Uri _u(String path) => baseUrl.resolve(path);

  Future<List<Note>> listNotes() async {
    final resp = await _client.get(_u('/v1/notes'), headers: _headers);
    _check(resp);
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => Note.fromApi(e as Map<String, dynamic>)).toList();
  }

  Future<Note> createNote(Note note) async {
    final resp = await _client.post(
      _u('/v1/notes'),
      headers: _headers,
      body: jsonEncode({
        'title': note.title,
        'body': note.body,
        'type': note.type,
        'tags': note.tags,
      }),
    );
    _check(resp);
    return Note.fromApi(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> pull(int since) async {
    final resp = await _client.get(_u('/v1/sync/pull?since=$since'), headers: _headers);
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> push(List<Map<String, dynamic>> changes,
      {String device = 'app'}) async {
    final resp = await _client.post(
      _u('/v1/sync/push'),
      headers: _headers,
      body: jsonEncode({'changes': changes, 'device': device}),
    );
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Enqueue a chat turn (async processing on server). Returns immediately.
  Future<
      ({
        String status,
        String? sessionId,
        String? userMessageId,
        String? assistantMessageId,
        String? language,
        int queuePosition,
      })> enqueueChatTurn(
    String message, {
    String? assistantLanguage,
    String? sessionId,
    List<Map<String, dynamic>> attachmentRefs = const [],
    Map<String, dynamic>? locationContext,
    bool persist = false,
  }) async {
    final resp = await _client.post(
      _u('/v1/chat'),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'assistant_language': ?assistantLanguage,
        'session_id': ?sessionId,
        'persist': persist,
        if (attachmentRefs.isNotEmpty) 'attachment_refs': attachmentRefs,
        if (locationContext != null) 'location_context': locationContext,
      }),
    );
    _check(resp);
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return (
      status: (j['status'] ?? 'accepted') as String,
      sessionId: j['session_id'] as String?,
      userMessageId: j['user_message_id'] as String?,
      assistantMessageId: (j['assistant_message_id'] ?? j['message_id']) as String?,
      language: j['language'] as String?,
      queuePosition: (j['queue_position'] as num?)?.toInt() ?? 1,
    );
  }

  /// @deprecated Use [enqueueChatTurn]. Kept as alias for tests migrating gradually.
  Future<
      ({
        String content,
        List<dynamic> toolCalls,
        String? sessionId,
        String? language,
        List<Map<String, dynamic>> pendingJobs,
        String? messageId,
      })> chat(
    String message, {
    String? assistantLanguage,
    String? sessionId,
    List<Map<String, dynamic>> attachmentRefs = const [],
  }) async {
    final accepted = await enqueueChatTurn(
      message,
      assistantLanguage: assistantLanguage,
      sessionId: sessionId,
      attachmentRefs: attachmentRefs,
    );
    return (
      content: '',
      toolCalls: const [],
      sessionId: accepted.sessionId,
      language: accepted.language,
      pendingJobs: const <Map<String, dynamic>>[],
      messageId: accepted.assistantMessageId,
    );
  }

  // --- Chat sessions (persistent multi-session history) -------------------- #

  Future<List<Map<String, dynamic>>> listSessions() async {
    final resp = await _client.get(_u('/v1/chat/sessions'), headers: _headers);
    _check(resp);
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createSession({String? title}) async {
    final resp = await _client.post(
      _u('/v1/chat/sessions'),
      headers: _headers,
      body: jsonEncode({'title': ?title}),
    );
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSession(String id) async {
    final resp = await _client.get(_u('/v1/chat/sessions/$id'), headers: _headers);
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> deleteSession(String id) async {
    final resp = await _client.delete(_u('/v1/chat/sessions/$id'), headers: _headers);
    _check(resp);
  }

  /// Upload a file for a chat session (images, documents, voice notes).
  Future<Map<String, dynamic>> uploadChatAttachment(
    String sessionId,
    String filename,
    Uint8List bytes, {
    String kind = 'file',
  }) async {
    final req = http.MultipartRequest(
      'POST',
      _u('/v1/chat/sessions/$sessionId/attachments'),
    )
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['kind'] = kind
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await _client
        .send(req)
        .timeout(const Duration(minutes: 2));
    final resp = await http.Response.fromStream(streamed);
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Uri chatAttachmentUrl(String sessionId, String filename) =>
      _u('/v1/chat/attachments/$sessionId/$filename');

  Future<Uint8List> downloadChatAttachment(String sessionId, String filename) async {
    final resp = await _client.get(
      chatAttachmentUrl(sessionId, filename),
      headers: {'Authorization': 'Bearer $token'},
    );
    _check(resp);
    return resp.bodyBytes;
  }

  Future<Map<String, dynamic>> saveChatAttachmentToNote(
    String sessionId,
    String filename, {
    String? notePath,
    String? title,
  }) async {
    final body = <String, dynamic>{};
    if (notePath != null) body['note_path'] = notePath;
    if (title != null) body['title'] = title;
    final resp = await _client.post(
      _u('/v1/chat/sessions/$sessionId/attachments/$filename/save-to-note'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> consolidateSession(String id) async {
    final resp = await _client.post(
      _u('/v1/chat/sessions/$id/consolidate'),
      headers: _headers,
    );
    _check(resp);
  }

  Future<Map<String, dynamic>> retryChatAction(
    String sessionId,
    String messageId, {
    String action = 'generate_image',
  }) async {
    final resp = await _client.post(
      _u('/v1/chat/sessions/$sessionId/messages/$messageId/retry-action'),
      headers: _headers,
      body: jsonEncode({'action': action}),
    );
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // --- Notifications (local "image ready" feed) ---------------------------- #

  Future<List<Map<String, dynamic>>> listNotifications({bool unreadOnly = true}) async {
    final uri = _u('/v1/notifications')
        .replace(queryParameters: {'unread_only': unreadOnly.toString()});
    final resp = await _client.get(uri, headers: _headers);
    _check(resp);
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> ackNotifications(List<String> ids) async {
    final resp = await _client.post(
      _u('/v1/notifications/ack'),
      headers: _headers,
      body: jsonEncode({'ids': ids}),
    );
    _check(resp);
  }

  /// SSE stream URL + headers for foreground notification subscription.
  Uri get notificationEventsUrl => _u('/v1/notifications/events');

  // --- Attachments --------------------------------------------------------- #

  /// Absolute URL to fetch an attachment's bytes (for `Image.network`).
  Uri attachmentUrl(String relPath) => _u('/v1/attachments/$relPath');

  /// Download attachment bytes from the server.
  Future<Uint8List> downloadAttachment(String relPath) async {
    final resp = await _client.get(
      attachmentUrl(relPath),
      headers: {'Authorization': 'Bearer $token'},
    );
    _check(resp);
    return resp.bodyBytes;
  }

  /// Bearer header for authenticated `Image.network` / streaming requests.
  Map<String, String> get authHeaders => {'Authorization': 'Bearer $token'};

  // --- Note CRUD (Phase 3) ------------------------------------------------- #

  Future<Note> getNote(String path) async {
    final resp = await _client.get(_u('/v1/notes/$path'), headers: _headers);
    _check(resp);
    return Note.fromApi(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<Note> updateNote(String path,
      {String? title, String? body, List<String>? tags, String? type}) async {
    final resp = await _client.put(
      _u('/v1/notes/$path'),
      headers: _headers,
      body: jsonEncode({
        'title': ?title,
        'body': ?body,
        'tags': ?tags,
        'type': ?type,
        'device': 'app',
      }),
    );
    _check(resp);
    return Note.fromApi(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Mark a note done (or reopen it). Done notes leave the review queue but
  /// stay readable by the assistant.
  Future<Note> markNoteDone(String path, bool done) async {
    final resp = await _client.put(
      _u('/v1/notes/$path'),
      headers: _headers,
      body: jsonEncode({'done': done, 'device': 'app'}),
    );
    _check(resp);
    return Note.fromApi(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> deleteNote(String path) async {
    final resp = await _client.delete(_u('/v1/notes/$path'), headers: _headers);
    _check(resp);
  }

  Future<String> uploadAttachment(
      String path, String filename, Uint8List bytes) async {
    final req = http.MultipartRequest('POST', _u('/v1/notes/$path/attachments'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await _client
        .send(req)
        .timeout(const Duration(minutes: 2));
    final resp = await http.Response.fromStream(streamed);
    _check(resp);
    return (jsonDecode(resp.body) as Map<String, dynamic>)['attachment'] as String;
  }

  Future<({String type, List<String> tags})> suggestTags({
    required String title,
    required String body,
  }) async {
    final resp = await _client.post(
      _u('/v1/notes/suggest-tags'),
      headers: _headers,
      body: jsonEncode({'title': title, 'body': body}),
    );
    _check(resp);
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return (
      type: (j['type'] ?? 'Note') as String,
      tags: ((j['tags'] ?? const []) as List).map((e) => e.toString()).toList(),
    );
  }

  Future<void> recordTagFeedback({
    required String text,
    required List<String> tags,
    String action = 'accepted',
  }) async {
    final resp = await _client.post(
      _u('/v1/feedback/tags'),
      headers: _headers,
      body: jsonEncode({'text': text, 'tags': tags, 'action': action}),
    );
    _check(resp);
  }

  Future<List<({String path, String? title})>> listDueNotes() async {
    final resp = await _client.get(_u('/v1/notes/due'), headers: _headers);
    _check(resp);
    final list = jsonDecode(resp.body) as List;
    return list
        .map((e) => (
              path: (e as Map<String, dynamic>)['path'] as String,
              title: e['title'] as String?,
            ))
        .toList();
  }

  Future<void> markNoteResurfaced(String path) async {
    final resp = await _client.post(
      _u('/v1/notes/$path/resurfaced'),
      headers: _headers,
    );
    _check(resp);
  }

  // --- AI features (Phase 4) ----------------------------------------------- #

  /// Kick off a web-search job; returns the finished job dict (server runs it
  /// to completion synchronously). `result.research` holds the OKF note path.
  Future<Map<String, dynamic>> search(String query,
      {List<String>? languages, double maxSeconds = 60}) async {
    final resp = await _client.post(
      _u('/v1/search'),
      headers: _headers,
      body: jsonEncode({
        'query': query,
        'languages': ?languages,
        'max_seconds': maxSeconds,
      }),
    );
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> enrich(String path, {String kind = 'idea'}) async {
    final resp = await _client.post(
      _u('/v1/enrich'),
      headers: _headers,
      body: jsonEncode({'path': path, 'kind': kind}),
    );
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<({Uint8List bytes, String contentType})> tts(
    String message, {
    String? assistantLanguage,
    String? sessionId,
  }) async {
    final resp = await _client.post(
      _u('/v1/voice/tts'),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'assistant_language': ?assistantLanguage,
        'session_id': ?sessionId,
      }),
    );
    _check(resp);
    final type = resp.headers['content-type']?.split(';').first.trim() ?? 'audio/wav';
    return (bytes: resp.bodyBytes, contentType: type);
  }

  /// Send recorded audio; returns transcript, reply text, and reply audio bytes.
  Future<({String transcript, String reply, Uint8List audio})> converse(
      Uint8List wav, {String? language}) async {
    final uri = _u('/v1/voice/converse')
        .replace(queryParameters: language != null ? {'language': language} : null);
    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', wav, filename: 'speech.wav'));
    final streamed = await _client.send(req);
    final resp = await http.Response.fromStream(streamed);
    _check(resp);
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return (
      transcript: j['transcript'] as String,
      reply: j['reply'] as String,
      audio: base64Decode(j['audio_base64'] as String),
    );
  }

  Future<Map<String, dynamic>> getJob(String jobId) async {
    final resp = await _client.get(_u('/v1/jobs/$jobId'), headers: _headers);
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // --- Settings / secrets (Phase 4) ---------------------------------------- #

  Future<Map<String, dynamic>> settings() async {
    final resp = await _client.get(_u('/v1/settings'), headers: _headers);
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> setSecret(String name, String value) async {
    final resp = await _client.post(
      _u('/v1/settings/secrets'),
      headers: _headers,
      body: jsonEncode({'name': name, 'value': value}),
    );
    _check(resp);
  }

  Future<void> deleteSecret(String name) async {
    final resp = await _client.delete(_u('/v1/settings/secrets/$name'), headers: _headers);
    _check(resp);
  }

  Future<Map<String, dynamic>> getVoiceRegistration() async {
    final resp = await _client.get(_u('/v1/settings/voice'), headers: _headers);
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> putVoiceRegistration({
    required String provider,
    required String apiKey,
    String? url,
    Map<String, String>? voices,
    String? model,
  }) async {
    final resp = await _client.put(
      _u('/v1/settings/voice'),
      headers: _headers,
      body: jsonEncode({
        'provider': provider,
        'api_key': apiKey,
        if (url != null && url.isNotEmpty) 'url': url,
        if (voices != null) 'voices': voices,
        if (model != null && model.isNotEmpty) 'model': model,
      }),
    );
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> deleteVoiceRegistration() async {
    final resp = await _client.delete(_u('/v1/settings/voice'), headers: _headers);
    _check(resp);
  }

  // --- Backup / restore (Phase 4) ------------------------------------------ #

  Future<Uint8List> backup({String? passphrase}) async {
    if (passphrase != null && passphrase.isNotEmpty) {
      final resp = await _client.post(
        _u('/v1/backup'),
        headers: _headers,
        body: jsonEncode({'passphrase': passphrase}),
      );
      _check(resp);
      return resp.bodyBytes;
    }
    final uri = _u('/v1/backup').replace(queryParameters: {'allow_plaintext': 'true'});
    final resp = await _client.get(uri, headers: _headers);
    _check(resp);
    return resp.bodyBytes;
  }

  Future<Map<String, dynamic>> restore(Uint8List bytes,
      {String filename = 'backup.zip', String? passphrase}) async {
    final req = http.MultipartRequest('POST', _u('/v1/backup/restore'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    if (passphrase != null && passphrase.isNotEmpty) {
      req.fields['passphrase'] = passphrase;
    }
    final streamed = await _client.send(req);
    final resp = await http.Response.fromStream(streamed);
    _check(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // --- Devices (Phase 1) --------------------------------------------------- #

  Future<List<Map<String, dynamic>>> listDevices() async {
    final resp = await _client.get(_u('/v1/auth/devices'), headers: _headers);
    _check(resp);
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> revokeDevice(String deviceId) async {
    final resp = await _client.delete(_u('/v1/auth/devices/$deviceId'), headers: _headers);
    _check(resp);
  }

  void _check(http.Response resp) {
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, resp.body);
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);
  @override
  String toString() => 'ApiException($statusCode): $body';
}
