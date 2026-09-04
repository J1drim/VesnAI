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

## Remaining delivery

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

- Dependency upgrades, CI/dependency automation, and service-image review.
- Desktop interaction, visual polish, responsive layouts, theme preferences.
- Pins/archive/saved views, indexed/semantic search, backlinks/related notes.
- Drafts/templates/shortcuts, history/Trash, project-scoped chat, native sharing.
- Graph navigation, cleanup suggestions, notification delivery, AI controls,
  performance measurements and remaining platform verification.
