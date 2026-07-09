"""Tests for SSR-safe external image URL ingest into chat attachments."""

from __future__ import annotations

from pathlib import Path

import pytest

from vesnai.ai.chat_image_ingest import (
    backfill_session_external_images,
    ingest_message_external_images,
)
from vesnai.ai.conversations import ConversationStore

POLLINATIONS = (
    "Oto obrazek:\n"
    "![cat](https://image.pollinations.ai/prompt/cat?width=1024&height=1024)"
)


@pytest.fixture
def store(tmp_path: Path) -> ConversationStore:
    return ConversationStore(tmp_path)


def test_ingest_fetches_url_and_strips_markdown(store: ConversationStore, monkeypatch):
    convo = store.create("Test")
    _, msg_id = store.append(convo.id, "assistant", POLLINATIONS)

    def fake_fetch(url: str):
        assert "pollinations" in url
        return b"\x89PNG", "image/png"

    monkeypatch.setattr(
        "vesnai.ai.chat_image_ingest.fetch_image_url",
        fake_fetch,
    )

    updated = ingest_message_external_images(store, convo.id, msg_id, POLLINATIONS)
    assert "pollinations" not in updated.lower()
    assert "Oto obrazek" in updated

    convo = store.get(convo.id)
    assert convo is not None
    msg = next(m for m in convo.messages if m.id == msg_id)
    assert len(msg.attachments) == 1
    assert msg.attachments[0]["kind"] == "fetched"
    assert msg.attachments[0]["mime"] == "image/png"


def test_ingest_skips_when_image_attachment_exists(store: ConversationStore, monkeypatch):
    convo = store.create("Test")
    _, msg_id = store.append(convo.id, "assistant", POLLINATIONS)
    store.add_message_attachment(
        convo.id,
        msg_id,
        {
            "path": "existing.png",
            "kind": "generated",
            "filename": "generated.png",
            "mime": "image/png",
        },
    )

    def fail_fetch(_url: str):
        raise AssertionError("fetch should not run when attachment exists")

    monkeypatch.setattr(
        "vesnai.ai.chat_image_ingest.fetch_image_url",
        fail_fetch,
    )

    updated = ingest_message_external_images(store, convo.id, msg_id, POLLINATIONS)
    assert "pollinations" not in updated.lower()


def test_backfill_updates_old_messages(store: ConversationStore, monkeypatch):
    convo = store.create("Test")
    _, msg_id = store.append(convo.id, "assistant", POLLINATIONS)

    monkeypatch.setattr(
        "vesnai.ai.chat_image_ingest.fetch_image_url",
        lambda _url: (b"\x89PNG", "image/png"),
    )

    count = backfill_session_external_images(store, convo.id)
    assert count == 1
    convo = store.get(convo.id)
    assert convo is not None
    msg = next(m for m in convo.messages if m.id == msg_id)
    assert msg.attachments
    assert "pollinations" not in msg.content.lower()
