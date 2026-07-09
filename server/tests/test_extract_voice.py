"""Attachment text extraction and voice (TTS/STT) round-trip."""

from __future__ import annotations

from vesnai.ai.chat import ChatService
from vesnai.ai.extract import default_extractor
from vesnai.ai.index import IndexService
from vesnai.ai.voice import VoiceService
from vesnai.notes import NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.providers.fakes import (
    FakeAIProvider,
    FakeEmbeddingProvider,
    FakeSTTProvider,
    FakeTTSProvider,
)


def test_extract_plaintext():
    assert "hello world" in default_extractor(b"hello world", "note.txt")


def test_extract_markdown():
    assert "heading" in default_extractor(b"# heading", "doc.md")


def test_extract_unknown_type_degrades_gracefully():
    # Unknown/binary types return empty text rather than raising.
    assert default_extractor(b"\x00\x01\x02", "mystery.bin") == ""


def test_extract_missing_native_lib_returns_empty():
    # PDF path with non-PDF bytes must not crash (best-effort extraction).
    assert default_extractor(b"not a pdf", "broken.pdf") == ""


def _voice(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FakeEmbeddingProvider())
    chat = ChatService(FakeAIProvider(), index, notes)
    return VoiceService(chat, FakeTTSProvider(), FakeSTTProvider("create a note about cats"))


def test_tts_produces_audio(tmp_path, fake_clock):
    voice = _voice(tmp_path, fake_clock)
    audio = voice.speak("hello there")
    assert isinstance(audio, bytes) and audio.startswith(b"VESNAI-FAKE-WAV")


def test_voice_converse_round_trip(tmp_path, fake_clock):
    voice = _voice(tmp_path, fake_clock)
    result = voice.converse(b"<fake audio bytes>")
    assert result.transcript == "create a note about cats"
    assert result.reply.content
    assert result.audio.startswith(b"VESNAI-FAKE-WAV")


def test_speak_forwards_language_to_tts(tmp_path, fake_clock):
    # The fake TTS encodes the language into its header, so we can assert the
    # reply is synthesized in the language of the user's turn.
    voice = _voice(tmp_path, fake_clock)
    assert b":pl:" in voice.speak("cześć", language="pl")
    assert b":en:" in voice.speak("hello", language="en")


def test_converse_speaks_in_transcription_language(tmp_path, fake_clock):
    voice = _voice(tmp_path, fake_clock)
    result = voice.converse(b"<fake audio bytes>", language="pl")
    assert b":pl:" in result.audio
