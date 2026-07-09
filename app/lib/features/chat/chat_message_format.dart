import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Formats chat message timestamps for display under bubbles.
String formatChatMessageSentAt(BuildContext context, DateTime sentAt) {
  final local = sentAt.toLocal();
  final locale = Localizations.localeOf(context).toString();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDay = DateTime(local.year, local.month, local.day);
  if (messageDay == today) {
    return DateFormat.jm(locale).format(local);
  }
  if (now.difference(local).inDays < 7) {
    return DateFormat.MMMd(locale).add_jm().format(local);
  }
  return DateFormat.yMMMd(locale).add_jm().format(local);
}

DateTime? parseChatMessageSentAt(String ts) {
  if (ts.trim().isEmpty) return null;
  return DateTime.tryParse(ts)?.toLocal();
}
