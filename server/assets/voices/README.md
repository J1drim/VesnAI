# Voice reference clips

Chatterbox Multilingual is a zero-shot voice-cloning TTS: it has no built-in
preset voices. The speaker timbre is taken from a short reference clip that we
ship here and pass as the `audio_prompt` for every synthesis, so the assistant
keeps one consistent voice across Polish and English.

## `vesna_pl_young_female.wav`

- Voice: young woman, Polish.
- Format: mono, 24 kHz, 16-bit PCM, ~7.7 s (normalized for Chatterbox; peak ~ -1 dBFS).
- License: Creative Commons Zero v1.0 Universal (CC0-1.0) — public domain, free
  for commercial use, no attribution required.
- Source: derived from a Mozilla Common Voice (Polish, `pl`) female recording,
  redistributed via the CC0 reference clip in
  [`Folx/chatterbox-ONNX-polish`](https://huggingface.co/Folx/chatterbox-ONNX-polish)
  (`polish-female-common-voice.wav`). Original Common Voice corpus is CC0-1.0.
- Per the Common Voice terms, the speaker's identity must not be determined or
  published; only the audio is used as a timbre reference.

### Why this clip

Selection follows the criteria in the bilingual-TTS plan: a clean,
single-speaker female Polish clip in the 5-10 s range with no clipping, so the
cloned voice sounds like a young woman and pronounces Polish diacritics
correctly. Because the same clip drives both `language_id="pl"` and
`language_id="en"`, the assistant sounds like the same person in either
language.

### Replacing the voice

Drop in any mono WAV (5-10 s, clean, single speaker; 24 kHz preferred) and point
`VESNAI_TTS_REFERENCE_WAV` at it. Keep the source license commercial-safe
(CC0 / CC BY with attribution) to stay within `docs/LICENSING.md`.

### If Polish sounds muddy or hard to understand

The reference clip strongly shapes pronunciation, so an unclear clip carries into
every reply. Things to try, in order:

- Use a cleaner clip: mono, 24 kHz, 5-10 s, a single speaker, no music/reverb and
  no clipping. The original `polish-female-common-voice.wav` from
  [`Folx/chatterbox-ONNX-polish`](https://huggingface.co/Folx/chatterbox-ONNX-polish)
  is a good A/B candidate if the bundled clip sounds off.
- Tune inference with the probe script and the `VESNAI_TTS_*` env vars documented
  in `docs/DEPLOYMENT.md` (lower temperature and `cfg_weight=0.5` usually help).

```bash
cd server
uv run --extra chatterbox python scripts/tts_probe_pl.py --reference-wav /path/to/clip.wav
```
