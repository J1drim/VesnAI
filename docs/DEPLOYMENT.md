# Deployment

VesnAI is designed to run on your own machine (e.g. an Apple Silicon Mac) and
store its knowledge in a directory you choose.

## Configuration: one file

All server settings live in a single `vesnai.yaml` (copy
`server/vesnai.example.yaml` and edit). Every setting can also be provided via
`VESNAI_*` env vars or CLI flags; precedence is **file < env < CLI**. Point at
a non-default location with `--config` or `$VESNAI_CONFIG`. Validate with
`uv run vesnai doctor` — it reports the resolved component stack (LLM, TTS,
STT, image, vector store, search) and flags configuration problems.

Bootstrap is **per-component**: on first online start the server downloads and
starts only what the config asks for (Ollama models, whisper weights, Docker
sidecars). A cloud-LLM-only config (`llm: openai_compatible`, `tts: none`,
`image: none`, `vector_store: in_memory`, `search: none`) needs neither Docker
nor Ollama.

## Option A - native (recommended on macOS)

```bash
cd server
uv sync
cp vesnai.example.yaml vesnai.yaml   # edit to taste
# HTTPS (recommended): install mkcert and generate a trusted dev certificate
../scripts/vesnai.sh setup-https
# The launcher binds 0.0.0.0 by default and prints the LAN URL to use in the app:
../scripts/vesnai.sh server
# (equivalent manual invocation)
uv run vesnai serve --host 0.0.0.0 --knowledge-dir ./knowledge \
  --cert ./localhost.pem --key ./localhost-key.pem
```

> The server must bind a LAN address (`--host 0.0.0.0`, the launcher default) so
> phones and tablets can reach it. Binding `127.0.0.1` only allows connections
> from the same machine. The launcher prints the exact `https://<lan-ip>:8443`
> URL to enter in the app.
>
> TLS **fails closed**: if `tls.enabled` is true (the default) but certs are
> missing or unreadable, the server refuses to start instead of silently
> falling back to plain HTTP. Use `--no-tls` only on trusted LANs.

The server advertises itself on the LAN via mDNS (`_vesnai._tcp`), so the mobile
and desktop apps can auto-discover it. Pair a device:

1. On the server host, run `uv run vesnai pair` (or
   `./scripts/vesnai.sh pair`). It authenticates to the running server with the
   **bootstrap secret** (generated into the data dir on first start, `0600`)
   and prints an 8-character pairing code + QR. Already-paired devices can also
   mint codes via `POST /v1/auth/pair/code` with their bearer token.
2. In the app's onboarding screen, tap a discovered server (or enter the LAN
   URL), then **Scan QR** or type the 8-character code (valid 5 minutes).
3. The app redeems the code at `POST /v1/auth/pair` and stores a per-device
   bearer token in the OS keychain/keystore.

For access away from home, see [REMOTE_ACCESS.md](REMOTE_ACCESS.md)
(pinggy / ngrok / cloudflared tunnels).

Manage paired devices via `GET /v1/auth/devices` and revoke one with
`DELETE /v1/auth/devices/{id}` (the app's Settings -> "Unpair this device" does
this for the current device).

### Mobile TLS (dev HTTPS)

The server uses a locally trusted certificate from [mkcert](https://github.com/FiloSottile/mkcert).
Mobile clients validate TLS through each platform's standard trust mechanisms — certificate
validation is never bypassed.

Dev mkcert trust is **opt-in**: release builds trust only system CAs. The
launcher passes `--dart-define=TRUST_DEV_MKCERT_CA=true` for dev builds it
produces; plain `flutter build` output never trusts the dev CA.

| Platform | Mechanism |
|----------|-----------|
| **Android** | With the dev define set, the mkcert root CA from `assets/certs/` is loaded into a Dart `SecurityContext` (no certificate bypass). Run `./scripts/vesnai.sh client install --device android` after `setup-https`. `network_security_config.xml` trusts user-installed CAs in **debug builds only**. |
| **iOS / iPadOS** | Install the mkcert root CA profile once (the install script prints steps). The app uses **URLSession** via `package:cupertino_http`. |
| **Desktop (Linux / Windows)** | With the dev define set, the mkcert root CA is loaded from `assets/certs/` into the Dart `SecurityContext`. |

If pairing fails with a certificate error on Android:

1. Regenerate the server cert so the LAN IP is in the certificate SANs:
   `./scripts/vesnai.sh setup-https`
2. Rebuild and reinstall the app:
   `./scripts/vesnai.sh client install --device android`
3. Enter the **LAN URL** printed when the server starts (not `localhost`).

For internet-facing deployments, use a publicly trusted certificate (e.g.
Let's Encrypt) or an HTTPS tunnel ([REMOTE_ACCESS.md](REMOTE_ACCESS.md)) — the
app validates public certs with no special build flags.

### Flutter dependencies

Keep plugin versions current so future Flutter releases do not fail on Swift Package
Manager (SPM) or built-in Kotlin migrations:

1. Run `cd app && flutter pub outdated` and upgrade direct dependencies (major bumps
   may need API migrations — see package changelogs).
2. After upgrading the Flutter SDK, read [Flutter breaking changes](https://docs.flutter.dev/release/breaking-changes)
   for SPM and built-in Kotlin.
3. Run `flutter build apk --release` locally and confirm there are no plugin
   compatibility warnings.
4. CI runs `scripts/check_flutter_deps.py` (fails if a direct dep is ≥2 major versions
   behind) and a release APK build that fails on SPM/KGP warnings.
5. Dependabot opens weekly pub PRs for `app/` and `packages/okf_dart`.

Temporary `dependency_overrides` in `app/pubspec.yaml` (`package_info_plus`,
`quill_native_bridge_windows`) bridge win32 6 compatibility until stable plugin
releases catch up — remove them when `flutter pub get` resolves without overrides.

Minimum deployment targets: **iOS 15**, **macOS 12** (required by `cupertino_http` 3.x).

### Mobile app: voice, sync, and widget

**Voice chat (native STT).** Speech is transcribed **on the phone** using the
platform recognizer (iOS Speech / Android `SpeechRecognizer`) for Polish (`pl_PL`)
and English (`en_US`). Tapping the mic shows the transcript live in the chat as you
speak; only the final text is sent to the server (`POST /v1/chat`) for the LLM reply.
Server-side Whisper is no longer in the chat path, so the user's words appear
immediately even when the model is slow. The optional "Speak" button on a reply uses
server TTS and now speaks in the **same language as your turn**: the app derives the
language from the recognizer locale (spoken) or from the text (typed) and passes it as
`language` to `POST /v1/voice/tts`. iOS additionally needs the speech-recognition
permission, which is declared in `Info.plist` (`NSSpeechRecognitionUsageDescription`).

**Bilingual voice (Polish + English).** TTS is **not** loaded inside the main
server by default. Register a provider in the app (**Settings → Voice service**):

| Provider | What you enter | Notes |
|---|---|---|
| **OpenAI** | OpenAI API key + voice ids (`nova`, `shimmer`, …) | Calls `api.openai.com/v1/audio/speech` (MP3). Switch from sidecar anytime — same screen. |
| **TTS sidecar** | Sidecar URL + API key + per-language voice IDs | Any self-hosted HTTP service implementing [TTS_SIDECAR.md](TTS_SIDECAR.md); WAV output |

Migration is a **settings change only**: pick a different provider, enter the new
API key, and save. The server routes all TTS through the same registration store
(`data_dir/voice.json` + encrypted `tts` secret).

Run `./scripts/vesnai.sh setup-https` once if mkcert certs are not generated yet.
Pair the app at the **`https://<lan-ip>:8443`** URL printed by the launcher.

**Licensing:** the VesnAI server and app remain **MIT** — they only call TTS over
HTTP. No TTS engine is bundled; copyleft/GPL engines can be self-hosted
behind the sidecar API if you choose. OpenAI is a paid external API
(your key, your account) — see [LICENSING.md](LICENSING.md).

**Optional in-process TTS**: set `VESNAI_TTS_ENGINE=chatterbox` with
`uv sync --extra ai --extra chatterbox` for voice-cloning multilingual TTS (MIT).
Chatterbox tuning env vars and the probe script
(`server/scripts/tts_probe_pl.py`) apply when that engine is selected.
**Breaking change:** `VESNAI_TTS_ENGINE=kokoro` was removed (GPL espeak-ng
dependency chain); use `chatterbox` or an external service instead.

**Persistent chat + memory.** Conversations are saved server-side under
`data_dir/conversations/` and listed in the chat drawer (new chat, switch, delete).
Durable memory uses Hermes-style split files in the knowledge bundle:

| File | Purpose |
|------|---------|
| `memory/memory.md` | Stable world facts |
| `memory/user.md` | Preferences and identity |
| `memory/projects.md` | Active work context |

The assistant updates memory **during the chat turn** via the `update_memory` tool
(not automatic post-turn extraction). Limits (env-configurable):

- `VESNAI_MEMORY_PROMPT_MAX_CHARS` (default 32k) — injected into the system prompt
- `VESNAI_MEMORY_DISK_MAX_CHARS` (default 100k) — total stored across memory files

A background memory review agent runs every `VESNAI_MEMORY_REVIEW_INTERVAL_TURNS`
user turns (default 10) without `update_memory`, or when you call
`POST /v1/chat/sessions/{id}/consolidate` (schedules async review).

Each chat session gets an append-only markdown transcript at
`memory/chats/{session_id}.md` in the knowledge bundle (saved automatically on
the server after every turn). After a reply that ran tools (created/linked notes),
the app resyncs notes and refreshes the graph so new notes appear without a restart.

**Self-tuning (Phase 8).**

- Tag feedback: `POST /v1/feedback/tags` — app sends tag edits; server retrains
  `TagClassifier` and blends it into `POST /v1/notes/suggest-tags`.
- Spaced resurfacing: `GET /v1/notes/due`, `POST /v1/notes/{path}/resurfaced` —
  Notes tab shows a “Due for review” section when paired.
- Playbooks: assistant saves procedures via `create_playbook` / `update_playbook`
  chat tools (OKF `Playbook` notes with `#skill` tag).
- Trajectories: chat turns append compact records to `data_dir/trajectories.jsonl`.

**Tool validation harness.**

- `VESNAI_CHAT_TURN_VALIDATION=true` (default) — after each turn, the reasoning
  model audits missing tool actions (any language). Disabled automatically in
  `offline_only` mode.
- `VESNAI_TOOL_POLICY_REVIEW_INTERVAL_HOURS` (default 24) — when enough audit
  failures appear in trajectories, an idle job appends learned bullets to
  `data/tool_policy.md`, injected into the chat system prompt.
- `VESNAI_TOOL_POLICY_REVIEW_MIN_FAILURES` (default 3) — minimum failed trajectories
  before policy review runs.
- Failed chat image jobs notify the client (`chat_image_failed`); retry via
  `POST /v1/chat/sessions/{id}/messages/{msg_id}/retry-action` with
  `{"action": "generate_image"}`.

**Auto-illustration + notifications.** Every new text note triggers a background
FLUX image (`VESNAI_AUTO_ILLUSTRATE`, default on; serialized so concurrent notes
don't thrash the GPU). When an image lands the server records an `image_ready`
event (`GET /v1/notifications`, `POST /v1/notifications/ack`,
`GET /v1/notifications/events` SSE); the app drains this feed on launch/resume and
polls while foregrounded, raising a local OS notification (no Firebase) and
resyncing so the picture shows on the note. A startup pass re-enqueues any text
note still missing its image.

**Attachments in notes.** Uploaded photos/files are stored in the bundle's
`attachments/`, recorded on the note's `vesnai.attachments`, and served by
`GET /v1/attachments/{path}` (authenticated). The note body renders as Markdown;
relative `attachments/...` image links are rewritten to that endpoint and loaded
with the bearer token, so photos and the auto-generated image appear inline. The
note screen has a view/edit toggle (rendered by default, pencil to edit raw), and
capture shows image thumbnails for pending attachments.

**First sync (seeing existing/AI-generated notes).** The app keeps an offline-first
local mirror and normally pulls only incremental server deltas. To make notes that
already exist on the server — including AI-generated ones — appear on a new device,
the app **backfills the full catalog** (`GET /v1/notes`) after pairing, on app resume,
and on every manual sync. If a note is on the server but not yet in the app, pull to
sync (or re-pair) once to backfill it.

**Edge-to-edge insets.** The app draws edge-to-edge (Android 15+); the shell and
feature screens use `SafeArea` so content and the bottom navigation clear the
gesture/3-button system bar.

**Android home-screen widget (Google Keep-style).** A Jetpack Glance widget shows a
header with **+ Note** / **Capture** actions and a scrollable list of recent notes;
tapping a note deep-links into the app (forwarded from `MainActivity` to Flutter as a
`widgetAction`), and the widget live-refreshes (`updateAll`) whenever the app writes a
new notes snapshot. After installing with
`./scripts/vesnai.sh client install --device android`, open the app once so it writes
the widget snapshot, then long-press the home screen → **Widgets** → **VesnAI** and
drop it on the home screen. The iOS WidgetKit extension is not yet linked in the Xcode
project and is out of scope for Android testing.

## Option B - Docker

```bash
cd server
docker compose up --build
```

Persists to the `vesnai-data` volume. Offline mode is on by default (no models
required). The server port is published **loopback-only**
(`127.0.0.1:8443`) — to expose it, use a tunnel or reverse proxy that
terminates TLS (see the commented override block in `docker-compose.yml` and
[REMOTE_ACCESS.md](REMOTE_ACCESS.md)).

For real local AI in Docker, start the bundled services with the `online`
profile (`docker compose --profile online up`) — it adds an **Ollama**
container alongside Qdrant/SearXNG — and set the `VESNAI_*` service URLs shown
in the compose file's comments. In-container bootstrap only pulls models
through APIs; whisper STT and FLUX image generation are **host-mode features**
(set `stt: none` / `image: none` in Docker, or run the server natively).

### Upgrading pinned sidecar images (Qdrant / SearXNG)

Qdrant and SearXNG images are pinned by **digest** in `server/docker-compose.yml`
(see `server/compose-images.lock.yaml` for the human-readable upstream tags).
This prevents silent supply-chain drift; when you intentionally bump a version,
follow the migration steps below so you do not lose data.

**What is stored where**

| Data | Location | Safe upgrade notes |
|------|----------|-------------------|
| Notes, attachments, memories | OKF `knowledge_dir` (host path) | Source of truth — back up with `POST /v1/backup` before major changes |
| Vector embeddings (semantic search) | Docker volume `qdrant-data` | Derived cache — VesnAI **reindexes all notes into Qdrant on every server start**, so a fresh/empty Qdrant volume is recoverable (slower first boot) |
| SearXNG config | `server/config/searxng/` (git) | No persistent search history in VesnAI |

**Never** run `docker volume rm qdrant-data` unless you explicitly want to discard
the embedding cache and rebuild it on the next server start.

**Routine digest bump (same Qdrant minor, e.g. 1.13.x)**

```bash
# 1. Pick a new upstream tag and record its digest
./scripts/compose-sidecars.sh pin-digest qdrant/qdrant:v1.13.2

# 2. Update server/docker-compose.yml and server/compose-images.lock.yaml

# 3. Backup + pull + recreate (automated)
./scripts/compose-sidecars.sh upgrade
```

`upgrade` always runs `backup` first (tarball under `~/VesnAI/backups/compose/` by
default). If Qdrant fails health checks after the bump, restore the volume:

```bash
./scripts/compose-sidecars.sh restore ~/VesnAI/backups/compose/qdrant-YYYYMMDD-HHMMSS.tar.gz
```

**Major Qdrant version jump (e.g. 1.13 → 1.14)**

1. Export an encrypted OKF backup (`POST /v1/backup` with passphrase).
2. Run `./scripts/compose-sidecars.sh backup`.
3. Update digests as above and run `upgrade`.
4. Restart the VesnAI server and verify semantic search.
5. If Qdrant refuses the old on-disk format, consult the
   [Qdrant upgrade guide](https://qdrant.tech/documentation/guides/upgrading/) or
   restore the volume tarball; as a last resort, remove only the Qdrant collection
   data inside the volume and restart the server to trigger a full reindex from notes.

SearXNG has no data volume — digest bumps only require `compose-sidecars.sh upgrade`
(or `docker compose pull searxng && docker compose up -d searxng`).

## Models on Apple Silicon (M-series, 64 GB)

Offline mode needs no models. To enable real local AI, install
[Ollama](https://ollama.com) and pull the defaults:

```bash
ollama pull qwen3.6      # chat + reasoning + vision (35B-A3B MoE, ~24 GB, Apache-2.0)
ollama pull bge-m3       # multilingual embeddings (1024-dim)
```

Then run with real providers (bootstraps Docker/Qdrant/SearXNG/Ollama automatically):

```bash
./scripts/vesnai.sh server --online --knowledge-dir ~/VesnAI/knowledge
```

Or manually:

```bash
uv run vesnai serve --no-offline --knowledge-dir ~/VesnAI/knowledge \
  --cert ./localhost.pem --key ./localhost-key.pem
```

On first online start the server:

1. Ensures Docker is running and starts **Qdrant** + **SearXNG** via `docker compose`
2. Starts **Ollama** if needed and **pulls** missing models (`qwen3.6`, `bge-m3`, …)
3. Installs/downloads **whisper.cpp** weights for STT
4. Installs the isolated **mflux** CLI (`uv tool install mflux`) for FLUX image gen
5. Wires real providers only (no fake fallback)

Disable model auto-pull with `VESNAI_OLLAMA_AUTO_PULL=false`.

### How the models are used

- **Chat / voice / tool-calling** uses `qwen3.6` with thinking OFF
  (`VESNAI_CHAT_THINKING=false`) for snappy, low-latency tool calls.
- **Reasoning** (web-search summarization, memory consolidation) uses the *same*
  resident weights with thinking ON (`VESNAI_REASONING_THINKING=true`) - no second
  model load, no extra RAM.
- **Photo captioning** uses `qwen3.6` multimodal to actually "see" the image.
- **Embeddings** use `bge-m3` (PL + EN). Image gen is FLUX.1-schnell via MLX/mflux,
  run from an **isolated CLI** (`uv tool install mflux` → `mflux-generate`). TTS is
  a **registered external service** (OpenAI or a self-hosted sidecar; register in
  Settings → Voice service) or optional in-process Chatterbox. STT is whisper.cpp
  `large-v3`.

#### FLUX model selection (gated HuggingFace repo)

Black Forest Labs **gated** `black-forest-labs/FLUX.1-schnell` on HuggingFace, so
pulling the official repo returns a 401 unless you are authenticated. VesnAI
defaults to this official repo, so authenticate **once** on the machine that runs
the server:

```bash
# 1. Accept the license (logged in) at:
#    https://huggingface.co/black-forest-labs/FLUX.1-schnell
# 2. Create a Read token at https://huggingface.co/settings/tokens
# 3. Log in (writes ~/.cache/huggingface/token, inherited by the mflux subprocess):
huggingface-cli login
# or set it in the server environment instead:
export HF_TOKEN=hf_xxxxxxxx
```

The model is controlled by these settings:

| Variable | Default | Notes |
|----------|---------|-------|
| `VESNAI_FLUX_MODEL` | `schnell` | builtin name (`schnell`/`dev`), HF repo id, or local path |
| `VESNAI_FLUX_BASE_MODEL` | _(unset)_ | `--base-model` for third-party repos/paths; leave unset for builtins |
| `VESNAI_FLUX_QUANTIZE` | `8` | `-q` value; leave unset for an already-quantized mirror |

**No-auth alternative.** If you would rather not authenticate, point the model at
an ungated, pre-quantized mflux mirror of the same Apache-2.0 weights:

```bash
export VESNAI_FLUX_MODEL=dhairyashil/FLUX.1-schnell-mflux-4bit
export VESNAI_FLUX_BASE_MODEL=schnell
unset VESNAI_FLUX_QUANTIZE   # the mirror is already 4-bit quantized
```

If a pull fails, the error now includes mflux's real stderr (e.g. a gated-repo
hint) instead of a bare exit code.

### Memory budget (64 GB)

- `qwen3.6` 35B-A3B resident ~24 GB + `bge-m3` ~1-2 GB + transient FLUX during
  image generation + Chatterbox TTS (~1-2 GB when loaded) + tiny whisper ->
  comfortable headroom.
- For maximum reasoning quality you can override
  `VESNAI_DEFAULT_REASONING_MODEL=qwen3.5:122b-a10b`, but at ~50 GB+ it evicts the
  other models and adds first-token latency, so it is opt-in.

All model choices are configurable in `vesnai.yaml` (`llm.models`, per role,
including a dedicated `marena` knob) or via `VESNAI_*` env vars (see
`server/vesnai/config.py` and `server/vesnai.example.yaml`).

### Live LLM tool tests (optional)

Verify the chat model actually calls tools (`update_memory`, `create_note`,
`create_playbook`) against a temp knowledge bundle:

```bash
cd server
uv sync --extra ai --extra dev   # needs ollama package + running daemon
uv run pytest -m live tests/test_live_llm_tools.py -v
```

Default `pytest` excludes `live` tests. Override model with
`VESNAI_TEST_CHAT_MODEL=qwen3.6`. Nightly CI runs `pytest -m live` when Ollama is
available on the runner.

## Backup & restore

- Download a full backup: `GET /v1/backup?allow_plaintext=true` (unencrypted zip,
  opt-in), or `POST /v1/backup` with JSON `{"passphrase": "..."}` for an
  encrypted (`VESNAIENC1`) blob.
- Restore: `POST /v1/backup/restore` with the zip; pass `passphrase` as a form
  field for encrypted backups.
- In the app: Settings -> Data -> "Back up knowledge" / "Restore from backup"
  (uses the system share sheet / file picker).
- Because the bundle is a git repo, you also get full history; all derived
  indexes (SQLite, Qdrant) are rebuildable from it.

## Storage location

Set `--knowledge-dir` (or `VESNAI_KNOWLEDGE_DIR`). That directory IS your data:
plain Markdown you can read, edit, and back up with any tool.
