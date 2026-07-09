# VesnAI - Personal Second Brain

VesnAI (named after the Slavic goddess of spring and renewal) is a privacy-first,
local-first personal knowledge assistant. All knowledge is stored canonically as
**OKF** (Google Open Knowledge Format v0.1) Markdown files in a directory you
choose, git-versioned for history and backup.

- **Scope**: single-user, multi-device (one owner, many paired devices).
- **Privacy**: data never leaves your devices/server unless you explicitly add an
  external API key.
- **Assistant**: a chat assistant with a girl voice that can store, recall, link
  and enrich your notes, run deep multilingual web searches, and improve over time.

## Repository layout

```
server/             FastAPI server: OKF store, sync, auth, jobs, AI services
packages/okf_dart/  Shared Dart OKF parser/serializer (used by the Flutter app)
app/                Flutter client (mobile + desktop) and native widget extensions
docs/               OKF profile, API/deploy docs, licensing register
fixtures/okf/       Cross-language OKF conformance fixtures (shared by Python + Dart)
```

## Quick start (one config file)

**New here?** See [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md) for step-by-step
paths (UI demo, full local AI, cloud LLM only) and a troubleshooting checklist.

The server is configured by a single `vesnai.yaml` file (everything in it can
also be set via `VESNAI_*` env vars or CLI flags — precedence: file < env < CLI):

```bash
cd server
uv sync
cp vesnai.example.yaml vesnai.yaml   # edit: pick your LLM, TTS, STT, image, search
uv run vesnai doctor                 # validate the config before starting
uv run vesnai serve                  # first start downloads exactly what you configured
uv run vesnai pair                   # mint a pairing code for the app (host-only)
# or: ../scripts/vesnai.sh pair
```

`vesnai.example.yaml` documents every section: `paths`, `network` (TLS on by
default), `llm` (local **Ollama** or any **OpenAI-compatible** endpoint —
OpenAI, OpenRouter, vLLM, llama.cpp, LM Studio — with per-role models including
a dedicated Marena critic model), `tts`, `stt` (whisper or none), `image`
(FLUX or none), `vector_store` (qdrant or in-memory), and `search` (SearXNG or
none). Bootstrap is **per-component**: a cloud-LLM-only setup with
`tts: none, image: none, vector_store: in_memory` needs no Docker and no
Ollama. Running `vesnai serve` with no configuration at all prints a friendly
first-run message instead of silently starting the offline demo.

> Using an OpenAI-compatible cloud provider sends note content to that
> endpoint — see the privacy note in `vesnai.example.yaml`.

**Platform support:** **macOS and Linux** share `./scripts/vesnai.sh` (mkcert can be
installed automatically on both). **Windows** uses `./scripts/vesnai.ps1` with the
same subcommands. You still install `uv`, Flutter, Docker, and Ollama yourself where
a path needs them — the launcher wires the rest.

**Remote access:** to use the app away from home, expose the server through an
HTTPS tunnel (pinggy / ngrok / cloudflared) — see
[docs/REMOTE_ACCESS.md](docs/REMOTE_ACCESS.md) and `scripts/tunnel.sh`.
Pairing is protected by a host-only bootstrap secret, so a tunneled stranger
cannot mint pairing codes.

## Launcher

A single OS-aware launcher runs the server and installs/updates the client.

**macOS / Linux** (`scripts/vesnai.sh`):

```bash
./scripts/vesnai.sh setup-https       # install mkcert + generate a trusted dev certificate (once)
./scripts/vesnai.sh server            # run the server over HTTPS (auto-runs setup if needed)
./scripts/vesnai.sh server --online   # use local models (Ollama) instead of offline fakes
./scripts/vesnai.sh client install    # build + install the desktop app
./scripts/vesnai.sh client install --device android  # release APK + dev TLS cert
./scripts/vesnai.sh client install --device ios      # release on iPhone/iPad
./scripts/vesnai.sh client update     # rebuild + replace an existing desktop install
./scripts/vesnai.sh client run        # hot-run on a device (e.g. --device android)
./scripts/vesnai.sh doctor            # check prerequisites (uv, flutter, mkcert, ollama)
```

**Windows** (`scripts/vesnai.ps1`): same commands, e.g.

```powershell
./scripts/vesnai.ps1 setup-https
./scripts/vesnai.ps1 server
```

The launcher needs [`uv`](https://docs.astral.sh/uv/) for the server and
[`flutter`](https://docs.flutter.dev/get-started/install) for the client.
Online mode also needs [Docker Desktop](https://docker.com/products/docker-desktop)
(for Qdrant + SearXNG) and [Ollama](https://ollama.com). The launcher runs
`uv sync --extra ai` and the server **bootstraps automatically** on first
`--online` start: Docker services, Ollama daemon, model pulls, and whisper.cpp.
No fake providers are used in online mode.

**Text-to-speech** is registered in **Settings → Voice service** — not bundled in
the main server. Pick **OpenAI** (cloud API key) or any **self-hosted TTS
sidecar** implementing the small HTTP contract in
[docs/TTS_SIDECAR.md](docs/TTS_SIDECAR.md). Switching providers is a settings
change only; no server reinstall. Copyleft/GPL TTS engines stay
out-of-tree by design — host any engine behind the sidecar HTTP API if you
want them.

Until registered, **Speak** in chat is disabled (HTTP 503). The VesnAI core stays
MIT — see [LICENSING.md](docs/LICENSING.md).

**Image generation** runs from its own isolated environment as a CLI tool: the
launcher (and bootstrap) run `uv tool install mflux`, and the server shells out to
`mflux-generate`. New text notes are auto-illustrated with a FLUX image in the
background (toggle with `VESNAI_AUTO_ILLUSTRATE=false`), and the app gets a local
notification when each image is ready. An optional in-process TTS engine remains
available for power users: `VESNAI_TTS_ENGINE=chatterbox` (MIT) with
`uv sync --extra ai --extra chatterbox`.

### Manual server / tests

```bash
cd server
uv sync
uv run vesnai serve --host 0.0.0.0 --knowledge-dir ./knowledge
uv run pytest
```

> Bind `--host 0.0.0.0` (the `scripts/vesnai.sh server` default) so phones and
> tablets on your LAN can pair; `127.0.0.1` is reachable only from the host
> machine. Mint a pairing code with `uv run vesnai pair` on the server host
> (it authenticates with the bootstrap secret stored in the data dir).

## Status

All nine phases of the plan are implemented and tested:

| Phase | Area | Where |
|---|---|---|
| 0 | Test foundation, provider interfaces, fixtures, CI, license check | `server/`, `.github/`, `fixtures/` |
| 1 | OKF server: store+git, auth, sync (deltas/version-vectors/conflicts), backup/restore, mDNS, jobs, observability | `server/vesnai/` |
| 2 | Flutter capture app, offline sync queue, shared `okf_dart`, on-device tagging, generated badge | `app/`, `packages/okf_dart/` |
| 3 | Desktop sticky-notes + iOS WidgetKit / Android Glance widgets + shared-storage contract | `app/lib/desktop/`, `app/ios/`, `app/android/` |
| 4 | Enrichment: embeddings (in-memory + Qdrant), idea images, photo captions, OCR/extraction | `server/vesnai/ai/` |
| 5 | Voice chat: RAG + tool-calling, girl-voice TTS + STT (interfaces), transcripts as OKF | `server/vesnai/ai/` |
| 6 | Deep multilingual web-search agent (planning, time budget, citations) | `server/vesnai/ai/search_agent.py` |
| 7 | Knowledge graph API + Flutter force-directed graph view | `server/vesnai/graph.py`, `app/lib/features/graph/` |
| 8 | Closed learning loop: split memory + `update_memory` tool, tag feedback/resurfacing/playbooks wired to API & chat; trajectories | `server/vesnai/ai/selftune.py`, `memory_review.py`, chat tools |
| 9 | Theme polish, encryption-at-rest backups, TLS, one-command deploy, a11y, docs | `app/lib/theme.dart`, `server/`, `docs/` |

All AI features run behind mockable provider interfaces, so the whole system is
testable and usable fully offline with deterministic fakes; real local models
(Ollama / FLUX / TTS sidecar / whisper.cpp / SearXNG) and Qdrant plug in via the same
interfaces when `offline_only` is disabled.

The client-server **device pairing** loop is fully wired end to end: live
in-process pairing codes + QR (`POST /v1/auth/pair/code`, printed on first run),
LAN binding, app onboarding with mDNS discovery and QR scanning, secure token
persistence, device listing/revocation, and in-app unpair. The Flutter app also
surfaces the full server feature set: durable SQLite (Drift) note mirror with a
persisted sync cursor, note edit/delete + attachments (photo/file/sketch),
web search, enrichment, voice chat (record + TTS), settings/secrets/voice service,
backup/restore, filtered knowledge graph, i18n (en/pl), and OS notifications.

**Test counts**: 79 server (pytest; 2 opt-in `ai`-extra tests skipped without
local models) + 11 OKF Dart + 28 Flutter (incl. golden) — green with
`ruff`/`mypy`/`dart analyze`/`flutter analyze` clean. Native widget tests
(XCTest / Robolectric) and the Flutter `integration_test` e2e run in the
nightly/platform CI suite.

See [docs/](docs/): [GETTING_STARTED](docs/GETTING_STARTED.md) ·
[OKF_PROFILE](docs/OKF_PROFILE.md) ·
[DEPLOYMENT](docs/DEPLOYMENT.md) · [CLIENTS](docs/CLIENTS.md) ·
[SECURITY](docs/SECURITY.md) · [LICENSING](docs/LICENSING.md) ·
[REMOTE_ACCESS](docs/REMOTE_ACCESS.md) · [TTS_SIDECAR](docs/TTS_SIDECAR.md).

## License

MIT - see [LICENSE](LICENSE). The VesnAI server and app are MIT; optional
external components run out-of-process:

| Component | License | How it's used |
|---|---|---|
| Ollama + models (qwen, bge-m3) | MIT / model-specific (Apache-2.0) | Local HTTP API |
| Qdrant | Apache-2.0 | Docker container |
| SearXNG | AGPL-3.0 | Docker container (network service, unmodified) |
| whisper.cpp | MIT | Subprocess |
| mflux / FLUX.1-schnell | Apache-2.0 | Isolated CLI tool |
| Chatterbox TTS (optional extra) | MIT | In-process, opt-in |
| TTS sidecar | yours | External HTTP service; GPL engines stay out-of-tree |
| zeroconf (mDNS) | LGPL-2.1 | Dynamically linked Python dependency |

See [docs/LICENSING.md](docs/LICENSING.md) for the full third-party / model
licensing register and [NOTICE](NOTICE) for attribution notes.
