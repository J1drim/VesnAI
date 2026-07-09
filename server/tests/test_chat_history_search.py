"""Tests for on-demand chat history search."""

from __future__ import annotations

from vesnai.ai.chat_history_search import search_conversation, search_session_messages
from vesnai.ai.conversations import ChatMessageRecord, Conversation


def test_search_session_messages_finds_keyword():
    messages = [
        ChatMessageRecord(role="user", content="portfolio sites", ts="", id="1"),
        ChatMessageRecord(role="assistant", content="Here are examples", ts="", id="2"),
        ChatMessageRecord(
            role="user", content="software house examples", ts="", id="3"
        ),
    ]
    hits = search_session_messages(messages, "software house", max_results=3)
    assert len(hits) == 1
    assert hits[0]["message_id"] == "3"
    assert "software house" in hits[0]["snippet"].lower()


def test_search_conversation_missing_session():
    result = search_conversation(None, "test")
    assert result["error"] == "session not found"
    assert result["matches"] == []


def test_search_conversation_limits_results():
    convo = Conversation(
        id="s1",
        title="t",
        created="",
        updated="",
        messages=[
            ChatMessageRecord(role="user", content="alpha one", ts="", id="a"),
            ChatMessageRecord(role="user", content="alpha two", ts="", id="b"),
            ChatMessageRecord(role="user", content="alpha three", ts="", id="c"),
        ],
    )
    result = search_conversation(convo, "alpha", max_results=2)
    assert len(result["matches"]) == 2
