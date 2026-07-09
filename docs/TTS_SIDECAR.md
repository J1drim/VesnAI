# TTS sidecar contract

VesnAI ships **no text-to-speech engine**. Voice output ("Speak" in chat) is
provided by an external service that you register in the app under
**Settings → Voice service**. Two provider types are supported:

1. **OpenAI-compatible speech API** (`provider: openai`) — OpenAI's
   `/v1/audio/speech` or any API that clones it. You supply the base URL
   (defaults to `https://api.openai.com/v1`), an API key, a model
   (e.g. `tts-1`), and per-language voice IDs (e.g. `nova`).
2. **TTS sidecar** (`provider: sidecar`) — any HTTP service you host that
   implements the small contract below. Copyleft or GPL-licensed engines can
   stay **outside** this MIT-licensed repository: they run in their own process,
   and VesnAI only ever talks HTTP to them.

Until a voice service is registered, `POST /v1/voice/tts` returns HTTP 503 and
the Speak button is disabled. Registration is stored server-side in
`data_dir/voice.json`; the API key goes into the encrypted secrets store.

## The sidecar HTTP contract

Your service must expose two endpoints:

### `GET /healthz`

No auth required. Returns HTTP 200 when the service is ready, e.g.:

```json
{ "status": "ok" }
```

The VesnAI server polls this during registration validation (and on online
bootstrap when a sidecar is registered).

### `POST /v1/synthesize`

Auth: `Authorization: Bearer <api-key>` — return **401** for a missing or
wrong key (VesnAI surfaces that as "voice service rejected the API key").

Request body (JSON):

```json
{
  "text": "Text to speak.",
  "voice": "engine-specific-voice-id",
  "language": "pl"
}
```

- `text` is always present.
- `voice` is sent when the caller picked a voice — either an explicit override
  or the per-language voice ID from the registration. Treat it as an opaque,
  engine-specific string.
- `language` (lowercase code such as `pl`, `en`) is sent **instead of**
  `voice` when no voice ID was resolved; pick a sensible default voice for
  that language.

Response: raw audio bytes with an audio content type. WAV
(`audio/wav`) is the safe choice — the app plays what the server relays.
Return 400 for unusable input and 5xx for engine failures.

### Voice IDs

Voice IDs are **your engine's** identifiers; VesnAI does not interpret them
and provides no defaults. When registering a sidecar in the app you must fill
in the per-language voice IDs (Polish and English) that your engine
understands.

## Wiring options

| Option | How |
|---|---|
| **Self-hosted sidecar** | Run any HTTP service that implements the contract below; register its URL, API key, and per-language voice IDs in the app. |
| OpenAI TTS | Built in — register `provider: openai` with your API key. No sidecar needed. |
| Any OpenAI-compatible speech API | Register `provider: openai` and change the URL to your endpoint (must implement `/audio/speech`). |
| In-process Chatterbox (MIT) | `VESNAI_TTS_ENGINE=chatterbox` + `uv sync --extra ai --extra chatterbox`; no HTTP service involved. |

## Licensing note

Copyleft/GPL TTS engines stay out-of-tree **by design**. Running a copyleft
engine as a separate self-hosted process is fine for personal use; if you
redistribute a bundled product containing one, review the license obligations
yourself. See [LICENSING.md](LICENSING.md).

## Registration helpers

- App UI: **Settings → Voice service** (provider, URL, API key, voice IDs).
- Headless: `server/scripts/write_voice_registration.py` writes
  `voice.json` + the secret directly into a server data dir, e.g.

```bash
cd server
uv run python scripts/write_voice_registration.py \
  --data-dir ./data --provider sidecar --url http://127.0.0.1:59125 \
  --api-key "$TTS_KEY" --voices-json '{"pl":"my-voice-pl","en":"my-voice-en"}'
```
