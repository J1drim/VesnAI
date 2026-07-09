import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_outside_widgets.dart';
import '../providers.dart';
import '../features/chat/chat_sessions.dart';
import '../features/graph/graph_screen.dart';
import 'notification_service.dart';

/// Set when a chat turn creates a note; [ChatScreen] shows a snackbar with Open.
final noteSavedPathProvider = StateProvider<String?>((ref) => null);

/// Drains the server's local notification feed, raises OS notifications, and
/// refreshes chat sessions when async turns complete.
class NotificationsService {
  final Ref _ref;
  Timer? _timer;
  bool _draining = false;

  NotificationsService(this._ref);

  AppLocalizations get _l10n =>
      localizationsForAppLocale(_ref.read(appLocaleProvider));

  static const _chatKinds = {
    'chat_turn_ready',
    'chat_turn_failed',
    'chat_image_ready',
    'chat_image_failed',
  };

  Future<void> drain() async {
    if (_draining) return;
    final client = _ref.read(apiClientProvider);
    if (client == null) return;
    _draining = true;
    try {
      final items = await client.listNotifications(unreadOnly: true);
      if (items.isEmpty) return;
      final notifier = _ref.read(notifierProvider);
      var refreshChat = false;
      var refreshNotes = false;
      var syncNotesAfterChat = false;
      String? savedNotePath;
      for (final n in items) {
        final kind = n['kind'] as String? ?? '';
        final title = (n['title'] as String?)?.trim();
        if (_chatKinds.contains(kind)) {
          refreshChat = true;
          if (kind == 'chat_turn_ready' || kind == 'chat_image_ready') {
            syncNotesAfterChat = true;
          }
          if (kind == 'chat_turn_ready') {
            final messageId = n['message_id'] as String?;
            final notePath = n['note_path'] as String?;
            if (notePath != null && notePath.isNotEmpty) {
              savedNotePath = notePath;
            }
            if (n['pending_image'] == true && messageId != null) {
              _ref.read(chatControllerProvider.notifier).markAwaitingImage(messageId);
            }
            await notifier.jobComplete(
              title?.isNotEmpty == true ? title! : _l10n.notifVesnaiReplied,
              _l10n.notifVesnaiRepliedBody,
              payload: 'chat',
            );
          } else if (kind == 'chat_image_ready') {
            await notifier.jobComplete(
              title?.isNotEmpty == true ? title! : _l10n.notifChatImageReady,
              _l10n.notifChatImageReadyBody,
              payload: 'chat',
            );
          } else if (kind == 'chat_image_failed') {
            final messageId = n['message_id'] as String?;
            _ref.read(chatControllerProvider.notifier).markImageActionFailed(messageId);
            await notifier.jobComplete(
              title?.isNotEmpty == true ? title! : _l10n.imageGenerationFailed,
              _l10n.notifImageGenFailedBody,
            );
          } else if (kind == 'chat_turn_failed') {
            await notifier.jobComplete(
              title?.isNotEmpty == true ? title! : _l10n.notifChatReplyFailed,
              _l10n.notifChatReplyFailedBody,
            );
          }
        } else if (kind == 'critique_ready') {
          refreshNotes = true;
          final critiquePath = n['note_path'] as String?;
          await notifier.jobComplete(
            title?.isNotEmpty == true ? title! : _l10n.notifMarenaCritique,
            _l10n.notifMarenaCritiqueBody,
            payload: critiquePath != null && critiquePath.isNotEmpty
                ? critiquePayload(critiquePath)
                : null,
          );
        } else {
          refreshNotes = true;
          final sourcePath = n['source_path'] as String?;
          await notifier.jobComplete(
            title?.isNotEmpty == true ? title! : _l10n.notifImageReady,
            _l10n.notifImageReadyBody,
            payload: sourcePath != null && sourcePath.isNotEmpty
                ? notePayload(sourcePath)
                : null,
          );
        }
      }
      final ids = items
          .map((e) => e['id'])
          .whereType<String>()
          .toList(growable: false);
      if (ids.isNotEmpty) {
        await client.ackNotifications(ids);
      }
      if (refreshNotes || syncNotesAfterChat) {
        await _ref.read(notesProvider.notifier).sync();
        _ref.invalidate(graphProvider);
      }
      if (savedNotePath != null) {
        _ref.read(noteSavedPathProvider.notifier).state = savedNotePath;
      }
      if (refreshChat) {
        await _ref.read(chatControllerProvider.notifier).refreshActiveSession();
      }
    } catch (_) {
      // Server unreachable / endpoint missing: try again on the next tick.
    } finally {
      _draining = false;
    }
  }

  /// Schedule (or clear) the daily offline "due for review" reminder based on
  /// the server's current due list. Fires at 9:00 local time even when the
  /// app stays closed.
  Future<void> refreshDueReviewReminder() async {
    final client = _ref.read(apiClientProvider);
    if (client == null) return;
    final notifier = _ref.read(notifierProvider);
    try {
      final due = await client.listDueNotes();
      if (due.isEmpty) {
        await notifier.cancelScheduled(kDueReviewNotificationId);
        return;
      }
      final body = due.length == 1
          ? _l10n.dueReviewSingle(due.first.title ?? due.first.path)
          : _l10n.dueReviewMultiple(due.length);
      await notifier.scheduleDailyReminder(
        id: kDueReviewNotificationId,
        title: _l10n.dueReviewTitle,
        body: body,
        hour: 9,
        minute: 0,
        payload: kDueReviewPayload,
      );
    } catch (_) {
      // Server unreachable; keep whatever reminder is already scheduled.
    }
  }

  void startPolling({Duration interval = const Duration(seconds: 5)}) {
    _timer ??= Timer.periodic(interval, (_) => drain());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }
}

final notificationsServiceProvider =
    Provider<NotificationsService>((ref) => NotificationsService(ref));
