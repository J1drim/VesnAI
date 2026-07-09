import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Max recent notes/chats written to the home-screen widget snapshot.
const kWidgetRecentsLimit = 10;

/// Contract for the small slice of state shared between the app and the native
/// home-screen widgets (iOS App Group / Android shared storage).
///
/// The app writes a compact "recent notes" snapshot and a pending quick-capture
/// inbox; the native widgets read recents to display and write quick captures
/// that the app drains on next launch/foreground. Keeping this as a pure,
/// serializable contract makes the bridge testable on both sides.
class WidgetSnapshot {
  final List<WidgetNote> recents;
  final List<WidgetChat> chatRecents;
  const WidgetSnapshot(this.recents, {this.chatRecents = const []});

  Map<String, dynamic> toJson() => {
        'version': 2,
        'recents': recents.map((n) => n.toJson()).toList(),
        'chatRecents': chatRecents.map((c) => c.toJson()).toList(),
      };

  factory WidgetSnapshot.fromJson(Map<String, dynamic> json) => WidgetSnapshot(
        ((json['recents'] ?? const []) as List)
            .map((e) => WidgetNote.fromJson(e as Map<String, dynamic>))
            .toList(),
        chatRecents: ((json['chatRecents'] ?? const []) as List)
            .map((e) => WidgetChat.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String encode() => jsonEncode(toJson());
  static WidgetSnapshot decode(String s) =>
      WidgetSnapshot.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

class WidgetNote {
  final String title;
  final String type;
  final bool generated;
  final String path;
  const WidgetNote({
    required this.title,
    this.type = 'Note',
    this.generated = false,
    this.path = '',
  });

  Map<String, dynamic> toJson() =>
      {'title': title, 'type': type, 'generated': generated, 'path': path};

  factory WidgetNote.fromJson(Map<String, dynamic> json) => WidgetNote(
        title: (json['title'] ?? '') as String,
        type: (json['type'] ?? 'Note') as String,
        generated: (json['generated'] ?? false) as bool,
        path: (json['path'] ?? '') as String,
      );
}

class WidgetChat {
  final String id;
  final String title;
  final String updated;
  const WidgetChat({required this.id, required this.title, this.updated = ''});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'updated': updated};

  factory WidgetChat.fromJson(Map<String, dynamic> json) => WidgetChat(
        id: (json['id'] ?? '') as String,
        title: (json['title'] ?? 'New chat') as String,
        updated: (json['updated'] ?? '') as String,
      );
}

/// A quick capture made from a home-screen widget, awaiting ingestion by the app.
class QuickCapture {
  final String text;
  final String createdIso;
  const QuickCapture(this.text, this.createdIso);

  Map<String, dynamic> toJson() => {'text': text, 'created': createdIso};
  factory QuickCapture.fromJson(Map<String, dynamic> json) =>
      QuickCapture((json['text'] ?? '') as String, (json['created'] ?? '') as String);
}

/// Abstraction over the platform-shared key/value blob. The native channel
/// implementation reads/writes the App Group (iOS) or shared file (Android);
/// the in-memory implementation backs tests.
abstract class SharedWidgetStorage {
  Future<void> writeSnapshot(WidgetSnapshot snapshot);
  Future<WidgetSnapshot?> readSnapshot();
  Future<List<QuickCapture>> drainQuickCaptures();
  Future<void> pushQuickCapture(QuickCapture capture);
}

class InMemorySharedWidgetStorage implements SharedWidgetStorage {
  WidgetSnapshot? _snapshot;
  final List<QuickCapture> _captures = [];

  @override
  Future<void> writeSnapshot(WidgetSnapshot snapshot) async => _snapshot = snapshot;

  @override
  Future<WidgetSnapshot?> readSnapshot() async => _snapshot;

  @override
  Future<List<QuickCapture>> drainQuickCaptures() async {
    final out = List<QuickCapture>.from(_captures);
    _captures.clear();
    return out;
  }

  @override
  Future<void> pushQuickCapture(QuickCapture capture) async => _captures.add(capture);
}

/// Platform-channel backed storage. Bridges to native code that persists the
/// blob in the shared container read by the home-screen widgets:
///   - Android: shared `SharedPreferences` (consumed by a Glance widget)
///   - iOS: an App Group `UserDefaults` suite (consumed by a WidgetKit widget)
/// On platforms without a native handler the calls fail gracefully (no-op).
class PlatformSharedWidgetStorage implements SharedWidgetStorage {
  static const _channel = MethodChannel('vesnai/widgets');

  const PlatformSharedWidgetStorage();

  @override
  Future<void> writeSnapshot(WidgetSnapshot snapshot) async {
    try {
      await _channel.invokeMethod<void>('writeSnapshot', snapshot.encode());
    } on MissingPluginException {
      // Native side not wired (e.g. desktop/tests): ignore.
    } on PlatformException catch (e) {
      debugPrint('widget writeSnapshot failed: $e');
      assert(() {
        throw FlutterError('widget writeSnapshot failed: $e');
      }());
    }
  }

  @override
  Future<WidgetSnapshot?> readSnapshot() async {
    try {
      final raw = await _channel.invokeMethod<String>('readSnapshot');
      return raw == null ? null : WidgetSnapshot.decode(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<List<QuickCapture>> drainQuickCaptures() async {
    try {
      final raw = await _channel.invokeMethod<String>('drainQuickCaptures');
      if (raw == null || raw.isEmpty) return const [];
      return (jsonDecode(raw) as List)
          .map((e) => QuickCapture.fromJson(e as Map<String, dynamic>))
          .toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  @override
  Future<void> pushQuickCapture(QuickCapture capture) async {
    try {
      await _channel.invokeMethod<void>('pushQuickCapture', jsonEncode(capture.toJson()));
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }
}
