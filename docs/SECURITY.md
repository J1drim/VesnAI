# Security & privacy

VesnAI is built around a strict privacy guarantee and defense-in-depth.

## Privacy guarantee

Your data never leaves your devices/server unless you explicitly configure an
external API key. The default is `offline_only=true`, in which the server uses
deterministic/local providers only and makes no outbound calls. This is enforced
by the provider factory and covered by tests.

## Authentication

- Device pairing: the server issues a short-lived **8-character alphanumeric
  code** (uppercase, no ambiguous characters); a device redeems it for a
  long-lived **per-device bearer token**. Tokens are stored **hashed**
  (`devices.json`, `0600` permissions), never in plaintext, and verified with
  a timing-safe comparison.
- Minting a pairing code (`POST /v1/auth/pair/code`) always requires either an
  already-paired device token or the **bootstrap secret** — a random secret
  generated into the data dir (`0600`) on first start and readable only on the
  server host (`vesnai pair` uses it automatically). There is **no loopback
  bypass**: requests from `127.0.0.1` get no special trust, so tunnels
  (which deliver all traffic as loopback) cannot mint codes.
- `POST /v1/auth/pair/code` and `POST /v1/auth/pair` (redeem) are rate-limited
  per client IP, plus a **global** cap on outstanding codes and total redeem
  attempts — behind a tunnel all traffic shares one IP, so per-IP limits alone
  would be worthless.
- Every `/v1/**` endpoint requires a valid token (see `require_device`). Health
  and metrics endpoints are intentionally open and expose no user content
  (`/readyz` does not report note counts).
- Tokens can be revoked per device.

## Secrets

External API keys are stored **encrypted at rest** (Fernet) under the data dir
with `0600` permissions, and are exposed by name only via the API. They are never
logged and never included in backups/exports. (Tests assert the value never
appears on disk in plaintext nor in the settings response.)

The Fernet master key (`secret.key`) is stored on disk with `0600` permissions;
protect the data directory with OS-level encryption (FileVault, LUKS) on
sensitive hosts.

## Transport

TLS is on by default for native installs and **fails closed**: when enabled but
certs are missing or unreadable, the server refuses to start instead of
silently serving plain HTTP. For local use, generate a trusted cert with
`mkcert` and pass `--cert/--key`. For internet exposure, terminate TLS with a
real cert (Let's Encrypt) or use an HTTPS tunnel
([REMOTE_ACCESS.md](REMOTE_ACCESS.md)). Disable only on trusted LANs with
`--no-tls`.

**Docker:** `docker-compose.yml` publishes the server port **loopback-only**
(`127.0.0.1:8443`) — nothing is exposed to the LAN or internet by default.
Expose it deliberately via a tunnel or a TLS-terminating reverse proxy (see the
commented override block in the compose file).

Mobile and desktop apps use each platform's native or explicitly configured HTTP
stack (iOS/macOS URLSession, Android/desktop Dart `SecurityContext` with declared
trust anchors). They validate server certificates normally and **release builds
trust only system CAs**; dev mkcert trust is opt-in via
`--dart-define=TRUST_DEV_MKCERT_CA=true` (bundled CA asset on Android/desktop,
installed profile on iOS), never by disabling TLS verification. Android's
network security config trusts user-installed CAs in debug builds only.

## Path-traversal protection

All bundle paths are resolved and verified to remain inside `knowledge_dir`;
absolute paths and `..` escapes are rejected (`PathTraversalError`).

Note attachment uploads sanitize filenames to `attachments/{uuid}-{basename}` so
uploaded names cannot escape the attachments prefix.

Sync push rejects writes to reserved paths (`index.md`, `log.md`, `memory/*`).

## Encryption-at-rest for backups

- **Encrypted export (recommended):** `POST /v1/backup` with JSON body
  `{"passphrase": "..."}` produces a passphrase-encrypted backup
  (PBKDF2-HMAC-SHA256 + Fernet, `VESNAIENC1` magic).
- **Plaintext export (opt-in):** `GET /v1/backup?allow_plaintext=true` returns an
  unencrypted zip. Requires an explicit flag so exports are never accidental.
- **Restore:** `POST /v1/backup/restore` multipart upload; pass the passphrase
  as a form field (not a URL query parameter).

The in-place bundle can additionally live on an encrypted volume / FileVault.

## Client data at rest

- Bearer tokens are stored in OS secure storage (`FlutterSecureStorage`).
- The local note mirror (Drift/SQLite), attachment caches, and widget snapshots
  are **not** encrypted by the app. Treat device backups and shared widget
  storage as sensitive; Android backup is disabled (`allowBackup=false`).

## AI / tool safety

- Web fetch uses SSRF checks and injection-phrase filtering (`web_safety.py`).
- RAG, memory, and extracted attachment text are sanitized before inclusion in
  LLM prompts.
- Post-turn **semantic validation** uses the reasoning model (Qwen, thinking on) to
  audit user intent vs assistant claims vs **tool receipts** (server-side execution
  log the model cannot forge). Regex phrase lists are fallback only when the audit
  fails or the server runs in `offline_only` mode.
- Structural checks (fake `sandbox:` image URLs, external markdown without a
  `generate_image` receipt) always run deterministically.
- Audit summaries are appended to `trajectories.jsonl` for idle tool-policy review;
  receipts are stored under `data/tool_receipts/` and are not exposed to the client
  except via derived message metadata (`pending_actions` status).
- Chat external image markdown (`![...](https://...)`) is ingested server-side:
  URLs pass SSRF validation and MIME/size checks (`fetch_image_url`), bytes are
  stored as message attachments, and markdown is stripped from stored content.
  The mobile client never loads arbitrary image URLs directly.

## Chat location (opt-in)

When the user enables **Share location with chat** in app Settings, the client may
attach approximate GPS (and an optional reverse-geocoded place label) to individual
chat requests. Location is **not** written into chat message history or session
records on the server; it is injected only as ephemeral turn context for that LLM
turn. The server may pass a place label into `web_search` query expansion for local
queries (weather, nearby). Disable the setting to stop sending location entirely.
Saved coordinates live in the device secure preferences store, not on the server.

## Docker sidecars

Qdrant and SearXNG bind to **127.0.0.1 only** (`6333`, `8888`) so the host-run VesnAI
server can reach them without exposing sidecars on the LAN. TTS is an external
service the user hosts and registers (Settings → Voice service); keep it bound to
localhost or a private network and protect it with its API key.

SearXNG's `secret_key` is **generated per deployment** (persisted under the
data dir with `0600` permissions and injected via the `SEARXNG_SECRET` env
var) — no shared constant is committed to the repo.

Third-party sidecar images (Qdrant, SearXNG) are pinned by digest in
`docker-compose.yml` with versions recorded in `compose-images.lock.yaml`.
Use `./scripts/compose-sidecars.sh backup` before digest bumps; see
[DEPLOYMENT.md](DEPLOYMENT.md) for the full upgrade/migration procedure.

## Known limitations (future work)

- All paired devices share one privilege level: any device can export/restore
  backups, manage secrets, and revoke other devices. Per-device roles are
  planned.
- Rate-limit state is in-process (resets on restart, not shared across
  workers).
- Attachment uploads enforce size limits but not MIME/content validation.

## Reporting

This is a personal-use project. If you find a vulnerability, please open a
private issue describing the impact and a reproduction.
