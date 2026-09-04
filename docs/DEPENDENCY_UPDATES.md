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
| flutter_markdown | Upstream marks it discontinued. Migrate to its maintained replacement alongside reader/chat rendering checks. |
| Image / voice environments | Updated lockfile resolves the declared mutually exclusive environments. Validate actual model execution on their intended hardware before deploying those optional upgrades. Core tests do not prove GPU/model compatibility. |
| Service images | Dependabot now watches Compose; coordinate digest changes with compose-images.lock.yaml and persisted-data checks. Never automatically roll out a sidecar upgrade to an existing knowledge installation. |
| Native tools | Gradle now has a weekly update job. Review Apple deployment targets and runtime-installed mflux alongside release builds. |

Review deferred items at the next release milestone and at least monthly. Record
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
