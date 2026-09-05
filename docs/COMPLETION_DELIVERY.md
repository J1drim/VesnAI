# Completion delivery and AI visibility

The server now acknowledges delivery per authenticated device. One device's
acknowledgement does not consume another's events. The legacy `read` field is
owner-wide state, separate from delivery; historical globally consumed events
are migrated as already delivered to avoid an upgrade burst. Feed writes use a
flushed temporary file and atomic replace. Corrupt existing JSON fails visibly
rather than being replaced with an empty feed.

Both foreground and background notification calls carry the server event ID.
The native notifier claims delivery in a separate SQLite ledger shared by
isolates/processes, then records completion. Notes are never locked while the
OS asks for notification permission. Claims expire after ten minutes so an
interrupted process can retry. Failed delivery releases its claim immediately.

Native IDs come from a persisted sequence and are stable on retry. ID 900001
remains reserved for obsolete-reminder cancellation. Bursts do not reuse a
second-based ID. Completed ledger records remain for deduplication; they contain
event IDs/state, not note content. Android uses `onlyAlertOnce` for replacements.
Exactly-once OS presentation is not claimed: a process can die after OS display
but before recording completion; retries reuse the same native ID, and platform
banner behavior can vary. Reinstalling/erasing local data resets this ledger.

Settings has a device-local completion-notification preference. Muted events
are consumed without asking for OS permission, while sync/background work
continues. Existing notifications are not retrospectively removed by this toggle.
Age-based reminders remain retired independently of that preference.

AI Settings displays server-managed automatic image/Marena flags and separates
demo, configured-but-unchecked, available-at-last-check and unavailable states.
An explicit check sends a small chat request and one embedding request (normal
provider costs may apply). It never generates images, voice or critiques.
Those services remain honestly labelled unprobed. Optional note enrichment is
still a deliberate note-menu action. Changing server-managed flags remains a
server configuration operation, not an unpersisted client toggle.

Tests cover independent delivery consumers, restart deduplication, failed retry,
1,000-event ID bursts, preference/permission behavior, per-device HTTP ack,
atomic-replace failure, legacy migration and explicit provider-check semantics.
Physical-device background/reboot and permission flows remain release checks.
