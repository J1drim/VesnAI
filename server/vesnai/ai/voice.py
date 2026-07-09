"""Voice layer for the chat assistant: TTS + STT.

Both sit behind provider interfaces (a registered HTTP voice service for TTS,
whisper.cpp for STT in production; deterministic fakes in tests), so the voice
chat round-trip is testable without audio models.
"""

from __future__ import annotations

from dataclasses import dataclass

from vesnai.ai.chat import ChatService, ChatTurn
from vesnai.ai.tts_text import detect_speech_language, prepare_for_tts
from vesnai.providers.base import STTProvider, TTSProvider


@dataclass
class VoiceReply:
    transcript: str
    reply: ChatTurn
    audio: bytes


class VoiceService:
    def __init__(
        self,
        chat: ChatService,
        tts: TTSProvider,
        stt: STTProvider | None = None,
        *,
        voice: str | None = None,
    ) -> None:
        self.chat = chat
        self.tts = tts
        self.stt = stt
        # None → use the TTS provider default (registered per-language voices).
        self.voice = voice

    def speak(self, text: str, *, language: str | None = None) -> bytes:
        # Strip markdown/code/URLs so the model speaks words, not punctuation.
        cleaned = prepare_for_tts(text)
        lang = detect_speech_language(cleaned, hint=language)
        return self.tts.synthesize(cleaned, voice=self.voice, language=lang)

    def transcribe(self, audio: bytes, *, language: str | None = None) -> str:
        if self.stt is None:
            raise RuntimeError("no STT provider configured")
        return self.stt.transcribe(audio, language=language)

    def converse(self, audio: bytes, *, language: str | None = None) -> VoiceReply:
        """Full voice round-trip: STT -> chat (with tools) -> TTS.

        The reply is spoken in the same language as the user's turn so the
        assistant answers Polish in Polish and English in English.
        """
        transcript = self.transcribe(audio, language=language)
        turn = self.chat.run(transcript)
        spoken = self.speak(turn.content, language=language)
        return VoiceReply(transcript=transcript, reply=turn, audio=spoken)
