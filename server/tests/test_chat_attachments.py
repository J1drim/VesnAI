"""Chat attachment upload and media preprocessing tests."""

from __future__ import annotations

from vesnai.ai.chat_media import ChatAttachment, build_user_message
from vesnai.ai.conversations import ConversationStore
from vesnai.providers.fakes import FakeSTTProvider


def test_conversation_attachment_roundtrip(tmp_path, fake_clock):
    store = ConversationStore(tmp_path, clock=fake_clock)
    convo = store.create()
    data = b"\x89PNG\r\n\x1a\nfake"
    meta = store.save_attachment(convo.id, "photo.png", data, kind="image")
    assert store.read_attachment(convo.id, meta["path"]) == data
    _, msg_id = store.append(
        convo.id, "user", "look at this", attachments=[meta]
    )
    fetched = store.get(convo.id)
    assert fetched.messages[-1].attachments[0]["path"] == meta["path"]
    assert msg_id


def test_build_user_message_includes_file_excerpt():
    _pdf_bytes = b"%PDF-1.4 minimal"
    msg = build_user_message(
        "summarize",
        [ChatAttachment(path="x", kind="file", filename="doc.txt", mime="text/plain")],
        read_bytes=lambda _: b"hello file content",
        stt=None,
    )
    assert "hello file content" in msg.content
    assert msg.images == []


def test_build_user_message_includes_image_bytes():
    msg = build_user_message(
        "what is this?",
        [ChatAttachment(path="p", kind="image", filename="a.png", mime="image/png")],
        read_bytes=lambda _: b"\x89PNG",
        stt=None,
    )
    assert msg.images == [b"\x89PNG"]


def test_build_user_message_transcribes_audio():
    msg = build_user_message(
        "",
        [ChatAttachment(path="a", kind="audio", filename="note.wav", mime="audio/wav")],
        read_bytes=lambda _: b"RIFF",
        stt=FakeSTTProvider("cześć VesnAI"),
    )
    assert "cześć VesnAI" in msg.content
