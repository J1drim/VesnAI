# Licensing register (commercial-use-safe)

VesnAI is MIT-licensed and only depends on components that are safe for
commercial use. This register is enforced in CI by a license-compliance check.

## Frameworks / libraries

| Component | License | Notes |
|---|---|---|
| Flutter / Dart | BSD-3-Clause | Clients |
| FastAPI / Starlette | MIT | Server API |
| Uvicorn | BSD-3-Clause | ASGI server |
| Pydantic | MIT | Models/config |
| structlog | Apache-2.0 / MIT | Logging |
| cryptography | Apache-2.0 / BSD | Secret encryption |
| zeroconf | LGPL-2.1 | mDNS discovery (dynamically linked) |
| Typer / Click | MIT / BSD | CLI |
| Qdrant (client + server) | Apache-2.0 | Optional vector DB |
| Drift / SQLite | MIT / Public Domain | Client local DB |
| flutter_force_directed_graph | MIT | Interactive knowledge graph (drag/zoom) |
| flutter_markdown | BSD-3-Clause | In-note Markdown + inline attachment images |
| flutter_local_notifications | BSD-3-Clause | Local "image ready" notifications (no Firebase) |
| Jetpack Glance | Apache-2.0 | Android home-screen widget |

## Models (optional, local)

| Capability | Default model | License | Notes |
|---|---|---|---|
| Chat / voice / tools | Qwen3.6 (35B-A3B MoE, via Ollama) | Apache-2.0 | `think:false` for low-latency tool-calling |
| Reasoning (jobs) | Qwen3.6 (same weights, `think:true`) | Apache-2.0 | Optional override `qwen3.5:122b-a10b` for max quality |
| Vision (captions) | Qwen3.6 multimodal (mmproj) | Apache-2.0 | "Sees" photos to caption them |
| Embeddings | bge-m3 (1024-dim, multilingual) | MIT | PL + EN; replaces nomic-embed-text |
| Image generation | FLUX.1-schnell (MLX/mflux) | Apache-2.0 | Avoids FLUX.1-dev non-commercial terms. Official repo is gated (needs HF login); an ungated mflux mirror (`dhairyashil/FLUX.1-schnell-mflux-4bit`) of the same Apache-2.0 weights is available via `VESNAI_FLUX_MODEL` |
| TTS (OpenAI) | `api.openai.com/v1/audio/speech` | Commercial API | Optional; register in Settings → Voice service (`provider: openai`) |
| TTS (external sidecar) | Any HTTP service implementing [TTS_SIDECAR.md](TTS_SIDECAR.md) | User's choice | Runs as a separate process the user hosts; not part of this repo. GPL engines (e.g. Piper) are allowed here because the server only talks HTTP |
| TTS (optional in-process) | Chatterbox Multilingual | MIT | Opt-in via `VESNAI_TTS_ENGINE=chatterbox` and `uv sync --extra ai --extra chatterbox` |
| STT | whisper.cpp (`large-v3`) | MIT | `distil-large-v3` for lower latency |
| Web search | SearXNG (self-hosted) | AGPL-3.0 | Self-hosting is fine; AGPL obligations apply only if offered to third parties |

## Optional copyleft services (separate process)

These are **not** Python dependencies of the MIT VesnAI server. They run as
optional external services the user starts and registers (URL + API key). The
main server talks to them over HTTP only.

| Service | License | Notes |
|---|---|---|
| SearXNG | AGPL-3.0 | Optional web search container; AGPL obligations apply only if offered to third parties |
| User-hosted TTS sidecar | Depends on engine | See [TTS_SIDECAR.md](TTS_SIDECAR.md); GPL engines such as `piper-tts` (OHF-Voice/piper1-gpl) stay out-of-tree by design |

## Excluded

- **MongoDB (SSPL)** - not OSI-permissive; VesnAI uses Qdrant + SQLite instead.
- **XTTS / non-commercial model weights** - excluded.
- **`piper-tts` and the Kokoro/espeak-ng chain (GPL-3.0)** - removed from this
  repo and its optional extras; use them only as self-hosted external sidecars.

## Inspiration

- **Hermes Agent** (Nous Research, MIT) - informed the closed learning-loop design
  (memory consolidation, skills, user model, resurfacing, trajectory compression).
  Honcho integration is deferred pending license review; VesnAI emulates the
  concept with its own `UserModel` concept.
