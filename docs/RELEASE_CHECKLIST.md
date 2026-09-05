# Upgrade release checklist

Implementation and local evidence: [UPGRADE_PROGRESS.md](UPGRADE_PROGRESS.md).
This checklist separates automated results from checks needing release devices,
signing credentials, model hardware or a deployment copy. It is not a claim that
the following manual checks have already passed.

## Before deploying to a real library

- Take an encrypted OKF backup, preserve local pending edits, and snapshot sidecar
  data consistently. Keep the previous server image/build for rollback. Trial on
  a copy first; do not downgrade migrated data in place.
- Deploy the upgraded server before testing attachment upload, recovery and
  project APIs. Older servers still accept text capture; unsupported attachment
  uploads remain queued rather than discarding the local file.
- Check CI for the exact delivered SHA. Normal push checks cover the Python and
  Dart suites, analyzer, advisory/license checks, native Android tests, Android
  APK, unsigned iOS app/extension and locked container startup/persistence.
  Dispatch CI with `live_models=false` for the Android emulator capture test.
- The container smoke uses a new UUID-named container and its own anonymous volume;
  both are deleted afterwards. It does not touch existing services/data. Only the
  locally built `vesnai/upgrade-smoke:20260905` test image/cache remains available
  for reproducing results; no production image tag was overwritten.

## Android and iOS physical-device pass

- Upgrade an old installation with notification 900001 scheduled. Launch unpaired
  and in airplane mode, resume, reboot and advance the test clock: no age-based
  reminder should return. Legacy taps open Notes. Cancellation must not prompt
  for permission. Verify ordinary job notifications with permission allowed,
  denied and the app preference muted; test burst delivery and foreground/
  background overlap on two devices.
- Edit the same synced base offline on two devices; reconnect, preview conflicts
  and exercise Keep mine/server/both. Repeat delete-versus-edit and editing during
  upload. Custom metadata and unsent edits must survive each path.
- Kill/restart during a draft with photos/files. Save offline, reconnect and open
  media from the other device. Delete a note with children/media, restore from
  Trash on another device, inspect history and restore a revision as a new edit.
- Share text, a URL, an image and multiple files from other apps while VesnAI is
  terminated and while running. Reopen offline; test retry, duplicate detection,
  changed text from the same source and explicit pending-copy discard. Check
  10-file/50 MB limits. Confirm an unfinished capture is not overwritten.
- Configure iOS App Group signing on both Runner and ShareExtension; the unsigned
  CI build does not establish provisioning. Android's current release build uses
  the existing debug signing configuration: configure production signing before
  distributing a store release. Do not commit signing secrets.

## Visual, performance and optional service checks

- Fixture screenshots cover phone/wide, EN/PL and light/dark with real fonts;
  large-text assertions pass. Verify screen reader labels, keyboard focus,
  reduced-motion behavior and resized native windows on release devices.
- Host benchmarks cover 100/1,000/10,000 notes; see
  [LIBRARY_DISCOVERY.md](LIBRARY_DISCOVERY.md). Measure scrolling frames, graph
  interaction and network sync on an agreed device before setting device targets.
  Host timings are not physical-device performance promises.
- Separate core+dev and AI environments were validated; image/voice combinations
  were resolution-checked without running live models. Run chosen image/voice
  tools on their supported hardware. Keep mutually exclusive image/Chatterbox
  extras isolated. Service availability checks explicitly send small paid/compute
  requests; demo output is not evidence of a working model backend.
- Review deferred dependency/sidecar/SDK migrations on **2026-10-05**. Set a
  validated `OLLAMA_IMAGE` digest for production. Do not upgrade Qdrant/SearXNG
  against existing data without copied-data and API compatibility checks.
- Windows/macOS release packaging and physical iOS widget tests are not covered
  by the current automated build matrix. Run them before distributing there.
