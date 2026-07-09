# Shared OKF conformance fixtures

These fixtures are consumed by **both** the Python OKF library (`server/`) and the
Dart OKF library (`packages/okf_dart/`) so the two implementations agree on the
OKF v0.1 rules.

- `valid/` - well-formed concepts (parse + conformance must pass).
- `invalid/` - concepts that must raise a conformance **error** (e.g. missing
  required `type` on a non-reserved file).

Rules exercised: required non-empty `type`, reserved files (`index.md`,
`log.md`) tolerated without a type, unknown fields preserved, broken cross-links
reported as warnings (not errors).
