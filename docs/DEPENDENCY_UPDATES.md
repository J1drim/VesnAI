# Dependency maintenance

## Validated baseline: September 2026

The upgrade addresses the versions proposed by Dependabot PRs #1–#6, using newer
compatible releases where appropriate: Drift 2.34.4 / drift_dev 2.34.6,
build_runner 2.15.1, mobile_scanner 7.4.0, share_plus 13.3.0, and YAML 3.1.4.
The shared Dart package and application commit their own consistent lockfiles.

File picker now uses stable 12.2.0 and its single-file/readAsBytes API. Editor
bridge 11.2.0 resolves a stable Windows implementation, allowing removal of both
temporary dependency overrides. The obsolete sqlite3_flutter_libs plugin is
removed; Drift already uses sqlite3 3.x native assets.

Reviewed upstream migration references:

- [Drift](https://pub.dev/packages/drift/changelog) and
  [generator](https://pub.dev/packages/drift_dev/changelog).
- [File picker API migration](https://pub.dev/packages/file_picker/changelog).
- [Share plugin](https://pub.dev/packages/share_plus/changelog) and
  [scanner](https://pub.dev/packages/mobile_scanner/changelog).
- [Editor bridge](https://pub.dev/packages/quill_native_bridge/changelog) and
  [SQLite native library retirement](https://pub.dev/packages/sqlite3_flutter_libs).

## Compatibility decisions and follow-up

| Item | Decision / next validation |
|---|---|
| Flutter / Dart | Current validated host uses Flutter 3.44.0 / Dart 3.12.0. Upgrade the SDK separately and review visual goldens before raising this baseline. |
| build_runner newer than 2.15.1 | Deferred: newer analyzer releases require a meta version incompatible with Flutter 3.44.0's test SDK pin. Revisit with the SDK update; do not override SDK-pinned packages. |
| Riverpod 3, secure storage 11, geocoding 5, just_audio 0.10 | Separate migrations; retain current compatible majors while storage/voice/UI changes are implemented. Reassess after the feature regression suite is in place. |
| flutter_markdown | Replaced by flutter_markdown_plus 1.0.12; migrated image callbacks and verified reader tasks/private attachments, chat, editor round trips and visual fixtures. |
| Image / voice environments | Updated lockfile resolves the declared mutually exclusive environments. Validate actual model execution on their intended hardware before deploying those optional upgrades. Core tests do not prove GPU/model compatibility. |
| Service images | Dependabot now watches Compose; coordinate digest changes with compose-images.lock.yaml and persisted-data checks. Never automatically roll out a sidecar upgrade to an existing knowledge installation. |
| Native tools | Gradle now has a weekly update job. Review Apple deployment targets and runtime-installed mflux alongside release builds. |

Next review date for every deferred item: **2026-10-05**, or earlier for a security
advisory. Review at each release milestone and at least monthly. Record
the tested platform and rationale when an update remains blocked.

## Ongoing workflow

Dependabot checks weekly. Python uses the `uv` ecosystem so updates follow
`pyproject.toml` and `uv.lock`. Drift and build-tool patch/minor updates are grouped;
major and other native-plugin updates remain individually reviewable. Container
and Android build dependencies have dedicated jobs. Configuration follows the
[GitHub options reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference).

For each update: review release notes, resolve and commit lockfiles, regenerate
affected code, run analyzers/tests, then build affected release targets. Use
locked installs in CI. A dependency failure must fail its workflow; analyzer
warnings are errors while informational migration notices remain visible.

The GitHub alert API currently reports security alerts disabled. The CI dependency
audit checks public advisories independently. Repository administrators can enable
GitHub alerts separately. A clean audit means no known findings in the checked
dependency set at that time, not a guarantee about all optional environments.
# SDK reproducibility follow-up

GitHub's floating stable channel installed Flutter 3.47.2, whose SDK-pinned
packages differ from the locally tested Flutter 3.44.0/Dart 3.12.0 lockfile.
Locked installation correctly failed rather than silently changing five
dependencies. Both Flutter CI jobs now pin 3.44.0. Upgrade that pin together
with regenerated locks, visual baselines and native builds in a dedicated SDK
migration; do not remove lock enforcement to hide the mismatch. Review the
3.47.x migration in the dedicated SDK follow-up on 2026-10-05.

## Final backlog disposition (2026-09-05 snapshot)

| Dependabot PR | Disposition |
|---|---|
| #1 drift_dev | Superseded by validated 2.34.6 on main. |
| #2 share_plus | Superseded by validated 13.3.0 on main. |
| #3 build_runner | Implemented at 2.15.1 on main. |
| #4 drift | Superseded by validated 2.34.4 on main. |
| #5 mobile_scanner | Implemented at 7.4.0 on main. |
| #6 shared YAML | Implemented at 3.1.4; PR is already closed. |
| #7 SearXNG digest | Deferred to 2026-10-05: retain recorded digest until real search/config compatibility is checked with a separate instance. No live sidecar rollout in this app upgrade. |
| #8 Qdrant digest | Deferred to 2026-10-05: test client/API compatibility and snapshot restore using a copied vector database before changing the production image register. |
| #9 Android library plugin 9.4 | Deferred to 2026-10-05 SDK migration: application/library plugins must move together with supported Gradle and Flutter built-in Kotlin/plugin compatibility, not just the library declaration. |
| #10 Robolectric | Updated to 4.16.1; all 11 native share/widget tests pass. |
| #11 Kotlin coroutines | Updated to 1.11.0; upstream Kotlin 2.2.20 metadata works with the project's 2.3.20 toolchain. Native tests and the release APK pass. |

The original PR branches are not merged on top of their newer replacements.
Dispositions are recorded here; stale PRs can be closed without reverting the
reviewed resolutions. Alerts remain unavailable because GitHub alerts are
disabled; offline/core dependency auditing is a separate CI gate.

Reviewed [Markdown continuation and API](https://pub.dev/packages/flutter_markdown_plus),
[coroutines release](https://github.com/Kotlin/kotlinx.coroutines/releases/tag/1.11.0)
and [Robolectric release](https://github.com/robolectric/robolectric/releases/tag/robolectric-4.16.1).

## Container and runtime review

- Python 3.12 image and uv 0.11.16 are digest-pinned in the Dockerfile and image
  register; Dependabot now covers both Dockerfiles and Compose. The runtime uses
  the locked `.venv`, eliminating the old second unpinned system installation.
- Docker build context explicitly excludes local data, credentials and virtual
  environments. The isolated container smoke test checks every installed version
  against uv.lock, API readiness, restart and disposable data persistence. It runs
  in CI and never mounts a real knowledge directory or an existing Docker volume.
- Debian OS packages are still resolved from the base distribution's apt
  repositories; preserve the built image digest for reproducible deployments.
  A pinned base alone does not make every later rebuild byte-for-byte identical.
- Qdrant/SearXNG pins remain unchanged. Ollama's `latest` fallback is explicitly
  development-only; production must set `OLLAMA_IMAGE` to a validated tag/digest.
  Its model/hardware smoke test and final digest selection are deferred to
  2026-10-05 with the sidecar review. No model downloads or running-service changes
  were made. Runtime mflux installation now selects 0.19.1, matching uv.lock,
  without forcibly replacing an existing user-managed tool. A regression test
  catches future lock/installer and Docker/register drift.
- Rollback: retain the previous server image by digest and take an encrypted OKF
  backup plus a consistent sidecar snapshot before rollout. Validate upgrades on
  copies; redeploy the prior image on its compatible snapshot if needed. Never
  downgrade a migrated database in place or erase the client's pending edits.

The container installation follows [uv's Docker environment guidance](https://docs.astral.sh/uv/guides/integration/docker/).
