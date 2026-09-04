# Upgrade implementation progress

Scope: [UPGRADE_PLAN.md](UPGRADE_PLAN.md). Each implementation commit is validated
locally and pushed to `main` as requested. Platform-specific checks that cannot run
on this host are explicitly recorded; they are not treated as passing.

## 2026-09-05 — Reminder retirement

- Removed the age-based scheduler, review UI, assistant tools, and review strings.
- Cancel legacy notification 900001 on launch and resume, including unpaired/offline
  use; cancellation does not request notification permission and retries on failure.
- Preserve legacy deep links and authenticated read-only API compatibility.
- Removed direct timezone packages and scheduled Android notification receivers;
  background-job notifications and WorkManager remain enabled.
- Added cancellation/retry and API metadata-preservation regression coverage.
- Validation: server suite 324 passed (4 live tests excluded); Ruff and mypy pass;
  Flutter suite 156 passed. Flutter analysis reports existing warnings/deprecations
  outside this change, with no errors. Physical device upgrade/reboot checks are
  not yet performed.

## Dependency triage

Dependency migration details and deferred SDK/major-version decisions are in
[DEPENDENCY_UPDATES.md](DEPENDENCY_UPDATES.md).

- Upgraded Flutter packages and stable native bridges: 156 Flutter tests and 11
  shared Dart tests passed; analysis passes with informational deprecations only.
- Updated Python lockfile: 324 offline tests, Ruff, mypy and 64-package license
  check pass. Separate AI environment: 47 focused tests and 76-package license
  check pass. Both installed-set and locked-export vulnerability audits report no
  known findings. Live image/voice model execution is not validated here.
- Android release APK builds successfully (93 MB). A final integration-test import
  ordering error was discovered after the dependency commit was queued; the next
  corrective commit fixes it; analysis now exits successfully with informational
  notices only. Workflow YAML parses successfully. Image and voice
  environment resolution passes dry runs, without installing those model stacks.
  Scheduled emulator execution and Apple/Windows release checks remain pending.

- Open Dependabot PRs: #1 drift_dev, #2 share_plus, #3 build_runner, #4 drift,
  #5 mobile_scanner, #6 yaml. Inspect compatible current versions together with
  their migration notes before updating lockfiles.
- GitHub reports Dependabot alerts disabled (403); no security-alert inventory
  was available. Do not infer that the dependency tree has no vulnerabilities.
- Development test dependencies installed from the existing lockfile into
  `/private/tmp/vesnai-upgrade-venv`; the installed server environment is unchanged.

## Sync reliability — implemented

- Explicit base revisions, canonical version acknowledgements, unique conflict
  copies and serialized bundle mutations; legacy divergent uploads retain both
  copies. Unknown metadata and server-owned identity/creation fields survive.
- Client network serialization, exact-revision acknowledgements, persistent
  conflict/deletion intent, and atomic pulled batches/cursor updates (schema 8).
- English/Polish pending status and readable Keep mine/server/both recovery.
  Protocol and single-writer deployment constraint: [SYNC_PROTOCOL.md](SYNC_PROTOCOL.md).
- Validation: 328 offline server tests passed (4 live excluded), Ruff and mypy
  pass; 161 Flutter tests passed; analyzer exits successfully with informational
  notices only. New tests cover concurrent same-base edits, acknowledgement
  replay, partial rejection, in-flight edits, deletion races, metadata persistence
  and transaction rollback. Physical multi-device recovery is not yet exercised.

## Remaining delivery (updated)

## Visual evolution — implemented

- Shared lazy Notes list/grid with working desktop capture, clickable and
  keyboard-activatable cards, compact tags, calmer surfaces and retained palette.
- Responsive navigation rail; persisted System/Light/Dark and list/card choices;
  constrained reader/chat width. Enlarged Polish title overflow found and fixed.
- 195 Flutter tests passed; analysis passes without errors/warnings. Includes 32
  layout combinations plus 1.8× text-scale checks, keyboard activation and
  preference persistence. Real-font/icon fixture screenshots generated and
  representative images visually reviewed; see [VISUAL_REVIEW.md](VISUAL_REVIEW.md).
- CI SDK drift found in remote checks and fixed separately by pinning Flutter
  3.44.0. Physical-device visual/native checks remain outstanding.

## Remaining delivery

## Organize and discover — implemented

- Synced pins/archive, device-local saved views and tag/type/status/order filters.
- SQLite FTS5 offline search, literal Unicode prefixes, title-weighted ranking,
  highlights, pagination and transactional schema-8-to-9 backfill.
- Explicit semantic library search with demo/unavailable states; offline
  backlinks/outgoing links and user-confirmed semantic Link actions.
- Validation: 202 Flutter tests passed (3 opt-in benchmarks skipped in normal
  suite), 329 offline server tests passed (4 live excluded), analyzer/Ruff/mypy
  pass. Separate 100/1,000/10,000-note host benchmark completed; method/results
  are in [LIBRARY_DISCOVERY.md](LIBRARY_DISCOVERY.md).
- Reviewed Linux golden artifact and restored its exact platform-specific
  baseline; no assertion tolerance/skip was introduced. Final GitHub CI checks
  are still required after all remaining implementation.

## Remaining delivery (updated)

- Dependency upgrades, CI/dependency automation, and service-image review.
- Native sharing.
- Graph navigation, cleanup suggestions, notification delivery, AI controls,
  performance measurements and remaining platform verification.

## Capture drafts — implemented

- SQLite draft metadata and atomic, content-addressed local attachment files;
  local-first save and persistent media upload queue with idempotent retries.
- Restored drafts, three localized templates, confirmed discard and conservative
  attachment cleanup; home new/search and capture save keyboard shortcuts.
- Details and compatibility: [CAPTURE_DRAFTS.md](CAPTURE_DRAFTS.md).
- Validation: 205 Flutter tests pass (3 opt-in benchmark skips), analyzer passes
  without errors/warnings; 330 offline server tests pass, Ruff and mypy pass.
  Capture data/widget tests
  cover restart, templates, offline retry ordering and media ownership.
- GitHub CI for the preceding organization and Linux-golden commits is green.

## History and Trash — implemented

- Authenticated per-note Git history, preview and base-checked restore as a new
  edit, including historical media without overwriting changed attachments.
- Server snapshots group deleted notes, enrichment children and attachments;
  another paired device can restore them. Explicit retention until discard.
- Local safety copies protect never-uploaded notes and keep their cached media.
  Restore as a separate pending note works offline; no automatic erasure.
- Validation: 207 Flutter tests pass (3 benchmark skips), analyzer passes;
  334 offline server tests pass, Ruff and mypy pass. Details and retention
  caveats: [RECOVERY.md](RECOVERY.md).

## Project spaces and scoped questions — implemented

- Saved-view project overviews with offline note/task/research counts and a
  device-persisted question interface with clickable note citations.
- Server-enforced path/filter intersection, bounded lexical excerpts, no tools
  or web access; explicit demo/unavailable states and pending-edit sync gate.
- Validation: 208 Flutter tests and 335 offline server tests pass; analyzer,
  Ruff and mypy pass. Scope and limitations: [PROJECTS.md](PROJECTS.md).
