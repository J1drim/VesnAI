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

- Open Dependabot PRs: #1 drift_dev, #2 share_plus, #3 build_runner, #4 drift,
  #5 mobile_scanner, #6 yaml. Inspect compatible current versions together with
  their migration notes before updating lockfiles.
- GitHub reports Dependabot alerts disabled (403); no security-alert inventory
  was available. Do not infer that the dependency tree has no vulnerabilities.
- Development test dependencies installed from the existing lockfile into
  `/private/tmp/vesnai-upgrade-venv`; the installed server environment is unchanged.

## Remaining delivery

- Dependency upgrades, CI/dependency automation, and service-image review.
- Sync concurrency, acknowledgements, atomic pulls, metadata, conflict recovery.
- Desktop interaction, visual polish, responsive layouts, theme preferences.
- Pins/archive/saved views, indexed/semantic search, backlinks/related notes.
- Drafts/templates/shortcuts, history/Trash, project-scoped chat, native sharing.
- Graph navigation, cleanup suggestions, notification delivery, AI controls,
  performance measurements and remaining platform verification.
