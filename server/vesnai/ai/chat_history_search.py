"""Keyword search over persisted chat session messages."""

from __future__ import annotations

from vesnai.ai.conversations import ChatMessageRecord, Conversation

DEFAULT_MAX_RESULTS = 5
SNIPPET_MAX_CHARS = 300


def search_session_messages(
    messages: list[ChatMessageRecord],
    query: str,
    *,
    max_results: int = DEFAULT_MAX_RESULTS,
) -> list[dict]:
    needle = (query or "").strip().lower()
    if not needle:
        return []
    limit = max(1, min(int(max_results or DEFAULT_MAX_RESULTS), 20))
    matches: list[dict] = []
    for msg in messages:
        content = msg.content or ""
        if not content or needle not in content.lower():
            continue
        matches.append(
            {
                "message_id": msg.id,
                "role": msg.role,
                "snippet": _snippet(content),
                "ts": msg.ts,
            }
        )
    return matches[-limit:]


def search_conversation(
    convo: Conversation | None,
    query: str,
    *,
    max_results: int = DEFAULT_MAX_RESULTS,
) -> dict:
    if convo is None:
        return {"error": "session not found", "matches": []}
    matches = search_session_messages(
        convo.messages, query, max_results=max_results
    )
    return {"matches": matches, "query": query.strip()}


def _snippet(text: str) -> str:
    text = text.strip()
    if len(text) <= SNIPPET_MAX_CHARS:
        return text
    return text[: SNIPPET_MAX_CHARS - 1] + "…"
