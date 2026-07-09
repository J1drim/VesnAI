"""Unit tests for the Chatterbox multilingual TTS provider.

The real model is never loaded: we stub ``_load`` with a fake that records the
language and returns a deterministic waveform, so we can assert preprocessing,
language mapping, and WAV framing without the ~0.5B model.
"""

from __future__ import annotations

import array
import io
import unicodedata
import wave

from vesnai.providers.chatterbox import ChatterboxTTSProvider, _preprocess


class _FakeModel:
    sr = 24000

    def __init__(self) -> None:
        self.calls: list[dict] = []

    def generate(self, text, *, language_id, audio_prompt_path, **kwargs):
        self.calls.append(
            {
                "text": text,
                "language_id": language_id,
                "audio_prompt_path": audio_prompt_path,
                **kwargs,
            }
        )
        # Quarter second of quiet noise as a float32 [-1, 1] waveform.
        n = self.sr // 4
        step = 0.2 / max(n - 1, 1)
        return array.array("f", (-0.1 + step * i for i in range(n)))


def _provider_with_fake() -> tuple[ChatterboxTTSProvider, _FakeModel]:
    provider = ChatterboxTTSProvider("/tmp/ref.wav")
    fake = _FakeModel()
    provider._model = fake  # skip from_pretrained
    return provider, fake


def test_preprocess_normalizes_and_lowercases():
    # NFKD + lowercase is required for Polish diacritic handling.
    assert _preprocess("  CZEŚĆ  ") == _preprocess("cześć")
    assert _preprocess("Hello WORLD") == "hello world"


def test_synthesize_maps_polish_language():
    provider, fake = _provider_with_fake()
    provider.synthesize("Cześć VesnAI", language="pl")
    assert fake.calls[0]["language_id"] == "pl"
    assert fake.calls[0]["audio_prompt_path"] == "/tmp/ref.wav"
    # Text is lowercased and NFKD-normalized (diacritics decomposed) for Chatterbox.
    assert fake.calls[0]["text"] == unicodedata.normalize("NFKD", "cześć vesnai")


def test_synthesize_defaults_unknown_language_to_english():
    provider, fake = _provider_with_fake()
    provider.synthesize("hi there", language="de")
    assert fake.calls[0]["language_id"] == "en"
    provider.synthesize("hi again", language=None)
    assert fake.calls[1]["language_id"] == "en"


def test_synthesize_returns_mono_24k_pcm16_wav():
    provider, _ = _provider_with_fake()
    audio = provider.synthesize("hello", language="en")
    with wave.open(io.BytesIO(audio), "rb") as wf:
        assert wf.getnchannels() == 1
        assert wf.getsampwidth() == 2
        assert wf.getframerate() == 24000
        assert wf.getnframes() > 0


def test_synthesize_empty_text_returns_no_audio():
    provider, fake = _provider_with_fake()
    assert provider.synthesize("   ", language="pl") == b""
    assert fake.calls == []


def test_synthesize_forwards_generation_params():
    provider = ChatterboxTTSProvider(
        "/tmp/ref.wav",
        exaggeration=0.35,
        cfg_weight=0.5,
        temperature=0.6,
        repetition_penalty=2.0,
    )
    fake = _FakeModel()
    provider._model = fake
    provider.synthesize("hello", language="en")
    call = fake.calls[0]
    assert call["exaggeration"] == 0.35
    assert call["cfg_weight"] == 0.5
    assert call["temperature"] == 0.6
    assert call["repetition_penalty"] == 2.0


def test_synthesize_chunks_long_text_and_concatenates():
    provider, fake = _provider_with_fake()
    long_text = " ".join(f"To jest zdanie numer {i}." for i in range(40))
    audio = provider.synthesize(long_text, language="pl")
    # Long input is split across multiple generate() calls...
    assert len(fake.calls) > 1
    # ...and the segments are stitched into one longer clip.
    with wave.open(io.BytesIO(audio), "rb") as wf:
        assert wf.getnframes() == len(fake.calls) * (fake.sr // 4)


def test_synthesize_short_text_uses_single_call():
    provider, fake = _provider_with_fake()
    provider.synthesize("Cześć, jak się masz?", language="pl")
    assert len(fake.calls) == 1
