"""Resolve assistant / TTS language for a chat session."""

from __future__ import annotations

from vesnai.ai.tts_text import detect_speech_language

SUPPORTED = frozenset({"pl", "en"})


def normalize_language(code: str | None) -> str | None:
    if not code:
        return None
    norm = code.lower().split("_", 1)[0]
    return norm if norm in SUPPORTED else None


def detect_conversation_language(messages) -> str | None:
    """Infer ``pl`` | ``en`` from recent user turns; ``None`` if no user text yet."""
    pl_score = 0
    en_score = 0
    for msg in reversed(messages):
        if msg.role != "user":
            continue
        if detect_speech_language(msg.content) == "pl":
            pl_score += 1
        else:
            en_score += 1
        if pl_score + en_score >= 5:
            break
    if pl_score > en_score:
        return "pl"
    if en_score > pl_score:
        return "en"
    for msg in reversed(messages):
        if msg.role == "user":
            return detect_speech_language(msg.content)
    return None


def resolve_language(
    *,
    user_setting: str | None = None,
    session_language: str | None = None,
    text: str | None = None,
) -> str:
    """Pick reply language for the chat model.

    Priority: fixed app setting → stored session language → detect from [text] → ``en``.
    """
    setting = (user_setting or "").lower()
    fixed = normalize_language(user_setting)
    if fixed and setting not in ("auto", ""):
        return fixed
    session = normalize_language(session_language)
    if session:
        return session
    if text and text.strip():
        return detect_speech_language(text)
    return "en"


def resolve_tts_language(
    *,
    user_setting: str | None = None,
    session_language: str | None = None,
    text: str | None = None,
) -> str:
    """Pick TTS voice language for a spoken assistant reply.

    Priority: fixed app setting → detect from spoken [text] → session language → ``en``.
    """
    setting = (user_setting or "").lower()
    fixed = normalize_language(user_setting)
    if fixed and setting not in ("auto", ""):
        return fixed
    if text and text.strip():
        return detect_speech_language(text, hint=session_language)
    session = normalize_language(session_language)
    if session:
        return session
    return "en"
