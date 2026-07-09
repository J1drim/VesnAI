# Getting started

VesnAI is **self-hosted**: you run the server on your machine and build/install
the Flutter app yourself. There are no GitHub Releases or App Store builds yet.

Pick a path below based on what you want to try.

| Path | Time (first run) | Real AI? | Best for |
|------|------------------|----------|----------|
| [A — UI demo](#path-a--ui-demo-offline) | ~5–15 min | No (fake AI) | Verify build, notes, sync |
| [B — Full local AI](#path-b--full-local-ai) | ~30–90 min | Yes (Ollama) | Privacy-first, full local stack |
| [C — Cloud LLM only](#path-c--cloud-llm-only) | ~15–30 min | Yes (OpenAI-compatible API) | Lighter hardware, no Docker/Ollama |

---

## Prerequisites (all paths)

Install before you start:

| Tool | Purpose |
|------|---------|
| [uv](https://docs.astral.sh/uv/) | Python server (3.12) |
| [Flutter stable](https://docs.flutter.dev/get-started/install) | Mobile + desktop app |
| [mkcert](https://github.com/FiloSottile/mkcert) | Trusted HTTPS for LAN pairing (`setup-https` can install it on macOS/Linux) |

**Platform:** **macOS and Linux** use `./scripts/vesnai.sh` — the bash examples below
apply on both. **Windows** uses the same subcommands via PowerShell:
`./scripts/vesnai.ps1` (`setup-https`, `server`, `server -Online`, `client install`,
`pair`, …).

```powershell
# Windows equivalent of the bash examples
./scripts/vesnai.ps1 setup-https
./scripts/vesnai.ps1 server
./scripts/vesnai.ps1 server -Online
./scripts/vesnai.ps1 pair
./scripts/vesnai.ps1 client install
```

---

## Path A — UI demo (offline)

Uses deterministic **fake AI** — good for testing the app shell, not for a real
assistant.

```bash
git clone https://github.com/<your-org>/second_brain_project.git
cd second_brain_project

./scripts/vesnai.sh setup-https          # once: mkcert + dev certificate
./scripts/vesnai.sh server               # default: offline fake AI

# Another terminal — build the app (desktop or phone):
./scripts/vesnai.sh client install       # or: --device android / ios

./scripts/vesnai.sh pair                 # prints 8-char code + server URL
```

In the app: enter the **LAN HTTPS URL** printed by the server (not `localhost`
on a phone), then the pairing code.

> **Important:** `./scripts/vesnai.sh server` defaults to **offline** mode.
> Chat replies are canned fakes until you use `--online` or Path C.

---

## Path B — Full local AI

Everything runs locally: Ollama, Qdrant, SearXNG, whisper, optional FLUX images.

**Also install:** [Docker Desktop](https://docker.com/products/docker-desktop),
[Ollama](https://ollama.com). Comfortable RAM: **~24 GB+** for default models
(`qwen3.6`, `bge-m3`).

```bash
git clone https://github.com/<your-org>/second_brain_project.git
cd second_brain_project

./scripts/vesnai.sh setup-https
./scripts/vesnai.sh server --online      # first start: pulls models, Docker sidecars (slow)

./scripts/vesnai.sh client install --device android   # example
./scripts/vesnai.sh pair
```

**Optional — Speak (TTS):** not bundled. Pick one:

- **OpenAI TTS** — register in app **Settings → Voice service** (API key + voice ids).
- **Self-hosted sidecar** — run any service that implements [TTS_SIDECAR.md](TTS_SIDECAR.md).
- **Chatterbox (MIT, in-process)** — `VESNAI_TTS_ENGINE=chatterbox` + `uv sync --extra ai --extra chatterbox`.

**Optional — auto note images (FLUX):** run `huggingface-cli login` once for the
gated official model, or point `VESNAI_FLUX_MODEL` at an ungated mirror
(see [DEPLOYMENT.md](DEPLOYMENT.md)).

Validate configuration anytime:

```bash
cd server && cp vesnai.example.yaml vesnai.yaml   # optional but recommended
uv run vesnai doctor
```

---

## Path C — Cloud LLM only

No Ollama, no Docker — uses an OpenAI-compatible API for chat/embeddings/vision.
**Note content is sent to that endpoint.**

```bash
git clone https://github.com/<your-org>/second_brain_project.git
cd second_brain_project

cd server
uv sync
cp vesnai.cloud.example.yaml vesnai.yaml
# Edit vesnai.yaml: set llm.api_key (or env:OPENAI_API_KEY) and models

uv run vesnai doctor
../scripts/vesnai.sh setup-https
uv run vesnai serve --host 0.0.0.0 \
  --cert ./localhost.pem --key ./localhost-key.pem --no-offline

# Another terminal:
../scripts/vesnai.sh client install
../scripts/vesnai.sh pair
```

Or use the launcher after editing yaml:

```bash
./scripts/vesnai.sh server --online   # --online skips offline fakes; yaml controls components
```

---

## Pairing a device

After security hardening, pairing codes are **8-character alphanumeric** strings.

1. Start the server.
2. On the **server host**, run `./scripts/vesnai.sh pair` (macOS/Linux) or
   `./scripts/vesnai.ps1 pair` (Windows), or `cd server && uv run vesnai pair`.
3. In the app onboarding (or Settings): enter `https://<lan-ip>:8443` and the code.

Already-paired devices can mint new codes from the app/API without the bootstrap
secret.

---

## Mobile HTTPS (dev)

Phones must trust your mkcert certificate:

- Build the app with **`./scripts/vesnai.sh client install`** (not plain
  `flutter build`) — the launcher passes `TRUST_DEV_MKCERT_CA=true`.
- **Android:** use the LAN IP URL from the server banner.
- **iOS:** install the mkcert root CA profile once (launcher prints steps on
  `client install --device ios`).

For access away from home without mkcert, use an HTTPS tunnel — see
[REMOTE_ACCESS.md](REMOTE_ACCESS.md).

---

## Checklist: “it works”

- [ ] Server reachable at `https://<lan-ip>:8443/healthz`
- [ ] Device paired (`./scripts/vesnai.sh pair`)
- [ ] App built via launcher (mkcert trust for dev HTTPS)
- [ ] Real chat: `--online` or `offline_only: false` in config
- [ ] Speak: voice service registered (**Settings → Voice service**)
- [ ] Images: mflux + HuggingFace auth, or disable `auto_illustrate`

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Chat gives nonsense / “fake” answers | You are in **offline** mode — use `server --online` or set `offline_only: false` |
| TLS / certificate error on phone | Re-run `setup-https`, rebuild app with launcher, use **LAN IP** not `localhost` |
| “Speech synthesis failed” | Re-register **Settings → Voice service**; sidecar API key must match `data/api_key` |
| Speak disabled (503) | No voice service registered yet |
| First `--online` start is slow | Normal — model pulls, Docker images, whisper weights |

More detail: [DEPLOYMENT.md](DEPLOYMENT.md) · [TTS_SIDECAR.md](TTS_SIDECAR.md) ·
[REMOTE_ACCESS.md](REMOTE_ACCESS.md) · [SECURITY.md](SECURITY.md)
