"""Chatterbox Multilingual text-to-speech (MIT, local voice cloning).

Chatterbox has no preset voices: a single reference clip (young Polish woman,
CC0 — see ``server/assets/voices/README.md``) defines the speaker timbre for
both Polish and English, so the assistant keeps one consistent voice across
languages. Only the ``language_id`` phoneme path changes per turn.
"""

from __future__ import annotations

import array
import io
import re
import time
import unicodedata
import wave
from pathlib import Path

from vesnai.observability import get_logger

log = get_logger("vesnai.providers.chatterbox")

# Languages we expose to the model; anything else falls back to English.
_SUPPORTED = {"pl", "en"}


class ChatterboxTTSProvider:
    def __init__(
        self,
        reference_wav: Path | str,
        *,
        device: str | None = None,
        exaggeration: float = 0.35,
        cfg_weight: float = 0.3,
        temperature: float = 0.4,
        repetition_penalty: float = 2.0,
    ) -> None:
        self.reference_wav = str(reference_wav)
        # Resolved lazily in _load(): picking a device imports torch, which is
        # only needed (or installed) where the real model actually runs.
        self.device = device
        self.exaggeration = exaggeration
        self.cfg_weight = cfg_weight
        self.temperature = temperature
        self.repetition_penalty = repetition_penalty
        self._model = None

    def _load(self):
        if self._model is None:
            from chatterbox.mtl_tts import ChatterboxMultilingualTTS

            if self.device is None:
                self.device = _default_device()
            start = time.monotonic()
            self._model = ChatterboxMultilingualTTS.from_pretrained(device=self.device)
            log.info(
                "chatterbox_loaded",
                device=self.device,
                seconds=round(time.monotonic() - start, 1),
            )
        return self._model

    def synthesize(
        self, text: str, *, voice: str | None = None, language: str | None = None
    ) -> bytes:
        cleaned = _preprocess(text)
        if not cleaned:
            return b""
        language_id = (language or "en").lower()
        if language_id not in _SUPPORTED:
            language_id = "en"
        model = self._load()
        sample_rate = getattr(model, "sr", 24000)
        # Long replies in one call make Chatterbox rush and hallucinate; split on
        # sentence boundaries and stitch the segments back into one clip.
        segments = [
            self._generate(model, chunk, language_id) for chunk in _chunk(cleaned)
        ]
        return _to_wav_bytes(_concat(segments), sample_rate)

    def _generate(self, model, text: str, language_id: str):
        return model.generate(
            text,
            language_id=language_id,
            audio_prompt_path=self.reference_wav,
            exaggeration=self.exaggeration,
            cfg_weight=self.cfg_weight,
            temperature=self.temperature,
            repetition_penalty=self.repetition_penalty,
        )


def _preprocess(text: str) -> str:
    # Chatterbox Multilingual expects NFKD-normalized, lowercase input; this is
    # required for correct Polish diacritic handling (per Resemble/Folx docs).
    return unicodedata.normalize("NFKD", text).strip().lower()


# Synthesize at most this many characters per generate() call. Short text is sent
# in one shot; longer replies are split on sentence boundaries.
_MAX_CHUNK_CHARS = 200
_SENTENCE_END = re.compile(r"(?<=[.!?…])\s+")


def _chunk(text: str) -> list[str]:
    if len(text) <= _MAX_CHUNK_CHARS:
        return [text]
    chunks: list[str] = []
    current = ""
    for sentence in _SENTENCE_END.split(text):
        sentence = sentence.strip()
        if not sentence:
            continue
        if current and len(current) + 1 + len(sentence) > _MAX_CHUNK_CHARS:
            chunks.append(current)
            current = sentence
        else:
            current = f"{current} {sentence}".strip()
    if current:
        chunks.append(current)
    return chunks or [text]


def _as_float_samples(seg) -> array.array:
    if hasattr(seg, "detach"):
        import numpy as np

        flat = np.asarray(seg.detach().cpu().numpy()).squeeze().ravel()
        return array.array("f", (float(x) for x in flat))
    if isinstance(seg, array.array):
        return seg
    return array.array("f", seg)


def _concat(segments: list) -> array.array:
    out = array.array("f")
    for seg in segments:
        out.extend(_as_float_samples(seg))
    return out


def _default_device() -> str:
    import torch

    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def _float_to_pcm16(samples: array.array) -> array.array:
    pcm16 = array.array("h")
    for x in samples:
        clamped = max(-1.0, min(1.0, x))
        pcm16.append(int(clamped * 32767))
    return pcm16


def _to_wav_bytes(wav, sample_rate: int) -> bytes:
    if hasattr(wav, "detach"):
        import numpy as np

        pcm = np.asarray(wav.detach().cpu().numpy()).squeeze()
        if pcm.dtype != np.int16:
            pcm = np.clip(pcm, -1.0, 1.0)
            pcm = (pcm * 32767).astype(np.int16)
        frames = pcm.tobytes()
    elif isinstance(wav, array.array) and wav.typecode == "h":
        frames = wav.tobytes()
    else:
        samples = wav if isinstance(wav, array.array) else array.array("f", wav)
        frames = _float_to_pcm16(samples).tobytes()
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(frames)
    return buf.getvalue()
