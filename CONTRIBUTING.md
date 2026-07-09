# Contributing to VesnAI

Thanks for your interest! VesnAI is a personal-use, privacy-first second brain.
Contributions are welcome — small, focused changes are easiest to review.

## Development setup

- **Server** (Python 3.12, [uv](https://docs.astral.sh/uv/)):

  ```bash
  cd server
  uv sync --extra dev
  uv run pytest -q
  uv run ruff check .
  uv run mypy vesnai
  ```

- **App** (Flutter, stable channel):

  ```bash
  cd app
  flutter pub get
  flutter analyze
  flutter test
  ```

- **OKF Dart package**:

  ```bash
  cd packages/okf_dart
  dart pub get && dart analyze && dart test
  ```

## Guidelines

- Keep the server core **MIT-compatible**. GPL/AGPL dependencies must stay
  out-of-process (external services), never bundled — see
  [docs/LICENSING.md](docs/LICENSING.md). CI runs a license check across the
  dependency extras.
- Never commit secrets, model weights (`*.onnx`, `*.bin`, `*.pt`), or personal
  data. CI runs a secrets scan (gitleaks).
- User-facing app strings go through l10n (`app/lib/l10n/*.arb`, English +
  Polish); run `flutter gen-l10n` after editing the `.arb` files.
- Add or update tests for behavior changes; keep `pytest`, `flutter test`, and
  the analyzers green.
- Configuration changes should be reflected in `server/vesnai.example.yaml`,
  `server/.env.example`, and the docs.

## Pull requests

1. Fork/branch, make the change, and confirm all checks above pass locally.
2. Describe **why** in the PR body, and note any breaking changes (they also
   belong in `CHANGELOG.md`).
3. One logical change per PR where possible.

## Reporting security issues

Please do not open public issues for vulnerabilities — see
[docs/SECURITY.md](docs/SECURITY.md#reporting).
