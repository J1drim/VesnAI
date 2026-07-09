"""On-demand tag and type suggestions for new notes."""

from __future__ import annotations

import json
import re
from typing import TYPE_CHECKING

from vesnai.providers.base import AIProvider

if TYPE_CHECKING:
    from vesnai.ai.selftune import TagClassifier

_WORD = re.compile(r"\w+", re.UNICODE)


def heuristic_tags(title: str, body: str) -> tuple[str, list[str]]:
    text = f"{title} {body}".lower()
    keywords = {
        "idea": ["idea", "maybe", "what if", "could", "startup"],
        "travel": ["trip", "travel", "flight", "visit", "vacation"],
        "todo": ["todo", "buy", "remember", "task", "call", "email"],
        "photo": ["photo", "picture", "image", "selfie"],
    }
    tags: list[str] = []
    for tag, words in keywords.items():
        if any(w in text for w in words):
            tags.append(tag)
    if not tags:
        tags = ["misc"]
    note_type = "Note"
    if "idea" in tags:
        note_type = "Idea"
    elif "photo" in tags:
        note_type = "Photo"
    elif "todo" in tags:
        note_type = "Task"
    return note_type, tags


def suggest_tags(
    ai: AIProvider,
    *,
    title: str,
    body: str,
    known_tags: list[str] | None = None,
    tag_classifier: TagClassifier | None = None,
) -> dict[str, object]:
    """Return ``{type, tags}`` using classifier, reasoning model, or heuristics."""
    text = f"{title} {body}".strip()
    if tag_classifier is not None and tag_classifier.is_trained:
        predicted = tag_classifier.predict(text, top_k=4)
        if predicted:
            note_type, _ = heuristic_tags(title, body)
            merged = list(dict.fromkeys([*predicted, *(known_tags or [])[:2]]))[:6]
            return {"type": note_type, "tags": merged}
    hint = ""
    if known_tags:
        hint = f"\nPrefer tags from this vocabulary when relevant: {', '.join(known_tags[:30])}."
    prompt = (
        "Suggest a note type and 3-6 lowercase tags for this personal note. "
        "Reply with JSON only: {\"type\": \"...\", \"tags\": [\"...\"]}."
        f"{hint}\n\nTitle: {title}\nBody: {body}"
    )
    try:
        raw = ai.complete(prompt, temperature=0.2, think=True).strip()
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
        data = json.loads(raw)
        tags = [str(t).lower().strip() for t in data.get("tags", []) if str(t).strip()]
        note_type = str(data.get("type") or "Note").strip() or "Note"
        if not tags:
            note_type, tags = heuristic_tags(title, body)
        return {"type": note_type, "tags": tags[:8]}
    except Exception:
        note_type, tags = heuristic_tags(title, body)
        return {"type": note_type, "tags": tags}
