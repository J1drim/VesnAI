import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../features/capture/capture_screen.dart';
import '../features/note_detail/note_detail_screen.dart';
import '../providers.dart';
import 'notification_service.dart';

typedef WidgetRefRead = T Function<T>(ProviderListenable<T> provider);

bool isValidWidgetNotePath(String? path) {
  if (path == null || path.isEmpty) return false;
  if (path.contains('..') || path.startsWith('/') || path.startsWith(r'\')) {
    return false;
  }
  if (!path.endsWith('.md')) return false;
  final base = path.split('/').last;
  if (base == 'index.md' || base == 'log.md') return false;
  if (path.startsWith('memory/')) return false;
  return true;
}

/// Handles deep links from the Android home-screen widget.
void handleWidgetAction(
  WidgetRefRead read, {
  required String? action,
  String? path,
  String? sessionId,
}) {
  switch (action) {
    case 'open_note':
      if (!isValidWidgetNotePath(path)) return;
      final nav = appNavigatorKey.currentState;
      if (nav == null) {
        read(pendingWidgetActionProvider.notifier).set(
          PendingWidgetAction(action: 'open_note', path: path),
        );
        return;
      }
      nav.push(MaterialPageRoute(builder: (_) => NoteDetailScreen(path: path!)));
      return;
    case 'capture':
    case 'new_note':
      final nav = appNavigatorKey.currentState;
      if (nav == null) {
        read(pendingWidgetActionProvider.notifier).set(
          PendingWidgetAction(action: action!),
        );
        return;
      }
      nav.push(MaterialPageRoute(builder: (_) => const CaptureScreen()));
      return;
    case 'open_chat':
      if (sessionId != null && sessionId.isNotEmpty) {
        read(homeTabRequestProvider.notifier).openChat(sessionId);
      } else {
        read(homeTabRequestProvider.notifier).newChat();
      }
      return;
    case 'new_chat':
      read(homeTabRequestProvider.notifier).newChat();
      return;
  }
}

/// Routes a tapped notification (payload string) to the matching screen.
/// `note:`/`critique:` payloads open the note detail; `chat` opens the chat
/// tab; `due_review` opens the notes tab (which shows the due section).
void handleNotificationPayload(WidgetRefRead read, String payload) {
  final target = parseNotificationPayload(payload);
  if (target == null) return;
  switch (target.kind) {
    case 'note':
    case 'critique':
      handleWidgetAction(read, action: 'open_note', path: target.path);
      return;
    case 'chat':
      read(homeTabRequestProvider.notifier).openChatTab();
      return;
    case 'due_review':
      read(homeTabRequestProvider.notifier).openNotesTab();
      return;
  }
}

void registerWidgetActionHandler(ProviderContainer container) {
  const channel = MethodChannel('vesnai/widgets');
  channel.setMethodCallHandler((call) async {
    if (call.method != 'widgetAction') return null;
    final args = (call.arguments as Map).cast<String, dynamic>();
    handleWidgetAction(
      container.read,
      action: args['action'] as String?,
      path: args['path'] as String?,
      sessionId: args['sessionId'] as String?,
    );
    return null;
  });
}
