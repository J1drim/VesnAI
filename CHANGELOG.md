# Changelog

All notable changes to VesnAI are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [2026.07.08.1-alpha] - 2026-07-08

### Alpha notice

First public alpha of **VesnAI** — a privacy-first, local-first personal knowledge
assistant. You self-host the server and build/install the Flutter client yourself;
there are no GitHub Releases or App Store builds yet.

**Tested so far:** the **server** and **Android app** have been used day-to-day.
**Desktop** (macOS, Linux, Windows) and **iOS** clients are implemented but have
not yet been exercised in real-world use and may have rough edges.

### Highlights

- Capture, edit, and sync notes as **OKF Markdown** — git-versioned on the server,
  mirrored offline on each device.
- Chat with an assistant that **recalls your notes**, creates and links them, runs
  **deep web research**, and generates images.
- **Pair multiple devices** over LAN HTTPS with mDNS discovery, QR codes, or a
  manual URL.
- Run **fully offline** with deterministic fake AI for UI testing, or switch to
  local models (Ollama) or a cloud OpenAI-compatible API.
- **Speak replies** when you register a voice service (OpenAI or a self-hosted
  HTTP sidecar).
- **Encrypted backups** of your knowledge bundle; secrets never leave the server
  in plaintext.

### Added — Knowledge & notes

- Canonical **OKF** (Open Knowledge Format v0.1) Markdown store with git history.
- Quick capture: notes, ideas, tasks, photos, file attachments, and sketches.
- On-device tag suggestions with server-side feedback to improve tagging over time.
- Note list with local search, type filters, task done/hide toggles, and pull-to-sync.
- Markdown view and WYSIWYG editing, task checklists, attachments, mark done/reopen.
- **Spaced resurfacing** — due notes surface for review on a schedule.
- **Auto-illustration** of new text notes with FLUX images (background job).
- Photo captioning and idea enrichment (background jobs).
- AI-generated content badge so generated notes and images are visually distinct.
- PDF text extraction and optional OCR on image attachments for search and chat context.

### Added — Chat assistant

- Multi-session chat with async turns, thinking state, queue position, and retry.
- **RAG** over your note embeddings plus **tool calling** — search, read, create,
  update, link, and delete notes from conversation.
- **Deep multilingual web search** — plans sub-queries, fetches sources, writes a
  cited Research note.
- On-demand **image generation** from chat; save chat attachments directly to a note.
- **Durable memory** split across `memory.md`, `user.md`, and `projects.md`.
- **Marena** idle adversarial critic — linked Critique notes for quality review.
- Optional **share location with chat** for web search (ephemeral, opt-in, not stored).
- Chat transcripts can be persisted as OKF concepts.
- Offline pending messages flush automatically when the server comes back.

### Added — Search & graph

- Dedicated **web search** screen reachable from the notes view.
- **Force-directed knowledge graph** built from your local note mirror.
- Graph filters by origin (user vs generated), note type, and tags; layout and zoom persist.

### Added — Voice & media

- **Speak**, replay, and optional auto-read-aloud for assistant replies (when a
  voice service is registered).
- Mic dictation in capture and chat composers (platform speech recognition).
- Server-side STT via whisper.cpp for uploaded audio; `/v1/voice/converse` bundles
  transcribe → chat → speak.
- TTS via **OpenAI-compatible API**, **self-hosted HTTP sidecar** (generic contract
  in `docs/TTS_SIDECAR.md`), or optional in-process **Chatterbox** (MIT extra).
- OS notifications when chat images are ready or fail, when research completes, and
  when notes are due for review.

### Added — Sync & multi-device

- Offline-first **SQLite (Drift) mirror** with delta sync, version vectors, and
  conflict reporting.
- **Device pairing** with 8-character alphanumeric codes; bootstrap secret required
  to mint codes on the server host (no loopback trust bypass).
- mDNS/Bonjour server discovery, QR scan pairing, device list and revocation.
- **Encrypted backup export** and restore from zip (passphrase-protected; plaintext
  export requires an explicit opt-in flag).
- **Android Glance** and **iOS WidgetKit** home-screen widgets with quick-capture
  deep links.
- Desktop **sticky-notes board** layout (macOS, Linux, Windows) — implemented but
  not yet validated in real-world use.

### Added — Security & privacy

- **`offline_only` default** — no outbound AI calls unless you configure them.
- **TLS on by default, fails closed** — server refuses to start with missing or
  invalid certificates instead of falling back to plain HTTP.
- Docker Compose publishes the server on **loopback only** (`127.0.0.1:8443`) by
  default; expose remotely via HTTPS tunnel or reverse proxy (`docs/REMOTE_ACCESS.md`).
- API keys and secrets **encrypted at rest** (Fernet); never returned in API responses
  or included in backups.
- Rate limits on pairing endpoints; device tokens stored hashed.
- AI safety: SSRF checks on web fetch, prompt sanitization, semantic audit against
  tool receipts, structural guardrails on tool actions.
- Release app builds trust **system CAs only**; dev mkcert trust is opt-in via the
  launcher (`TRUST_DEV_MKCERT_CA=true`).
- SearXNG `secret_key` generated per deployment, not committed to the repo.

### Added — Configuration & deployment

- Single-file **`vesnai.yaml`** configuration with precedence file < env < CLI
  (see `server/vesnai.example.yaml` and `server/.env.example`).
- **`vesnai doctor`** validates the resolved stack before starting.
- **LLM providers:** local Ollama or any **OpenAI-compatible** endpoint (OpenAI,
  OpenRouter, vLLM, llama.cpp server, LM Studio) with per-role models including a
  dedicated Marena critic model.
- **Per-component bootstrap** — only configured components are installed/started;
  a cloud-LLM-only setup needs no Docker or Ollama.
- Three documented setup paths: offline UI demo, full local AI, cloud LLM only
  (`docs/GETTING_STARTED.md`).
- Launchers: `./scripts/vesnai.sh` (macOS/Linux) and `./scripts/vesnai.ps1`
  (Windows) — `setup-https`, `server`, `client install`, `pair`, `doctor`, and more.
- Remote access helper (`scripts/tunnel.sh`) for pinggy / ngrok / cloudflared.

### Added — Localization

- Full app localization in **English** and **Polish** — onboarding, notes, chat,
  graph, search, settings, desktop sticky board, error paths, and unpaired banner.
- Per-app language setting and separate assistant reply language.

### Known limitations (alpha)

- **No prebuilt binaries** — clone, configure, build, and pair yourself.
- **Platform coverage:** only the **server** and **Android app** have been used in
  practice so far; **desktop** (macOS, Linux, Windows) and **iOS** clients are
  untested in real-world use and may have rough edges.
- **TTS is not bundled** — register OpenAI or a self-hosted HTTP sidecar in
  Settings → Voice service; Speak is disabled until then.
- **First `--online` start is slow** — model pulls, Docker images, and whisper
  weights download on first run.
- **Full local AI** needs Docker, Ollama, and comfortable RAM (~24 GB+ for default
  models).
- **Cloud LLM path** sends note content to your configured endpoint — review the
  privacy note in `vesnai.example.yaml`.
- Native widget tests (XCTest / Robolectric) and Flutter `integration_test` e2e run
  in nightly/platform CI, not every PR.

## Unreleased

Nothing yet.
