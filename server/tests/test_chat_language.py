"""Tests for chat session language detection and resolution."""

from __future__ import annotations

from vesnai.ai.chat_language import (
    detect_conversation_language,
    resolve_language,
)
from vesnai.ai.conversations import ChatMessageRecord, ConversationStore


def test_detect_conversation_language_from_user_turns():
    messages = [
        ChatMessageRecord(role="user", content="Jaka jest pogoda?", ts="1"),
        ChatMessageRecord(role="assistant", content="Słonecznie.", ts="2"),
        ChatMessageRecord(role="user", content="A jutro też?", ts="3"),
    ]
    assert detect_conversation_language(messages) == "pl"


def test_resolve_language_prefers_user_setting():
    assert (
        resolve_language(user_setting="en", session_language="pl", text="Dziś pada.")
        == "en"
    )


def test_resolve_language_uses_session_when_auto():
    assert (
        resolve_language(user_setting="auto", session_language="pl", text="Hello")
        == "pl"
    )


def test_resolve_language_detects_from_text():
    assert resolve_language(user_setting=None, session_language=None, text="Cześć!") == "pl"


def test_resolve_tts_language_prefers_spoken_text_over_session():
    from vesnai.ai.chat_language import resolve_tts_language

    assert (
        resolve_tts_language(
            user_setting=None,
            session_language="en",
            text="To jest odpowiedź po polsku.",
        )
        == "pl"
    )


def test_conversation_store_refresh_language(tmp_path, fake_clock):
    store = ConversationStore(tmp_path, clock=fake_clock)
    convo = store.create()
    store.append(convo.id, "user", "Jaka jest pogoda w Warszawie?")
    updated = store.refresh_language(convo.id)
    assert updated.language == "pl"
