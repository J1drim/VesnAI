"""Tests for chat note tool helpers."""

from __future__ import annotations

from vesnai.ai.chat import NOTE_ACCESS_RULES, ChatService, build_system_content
from vesnai.ai.conversations import ConversationStore
from vesnai.ai.index import IndexService
from vesnai.ai.note_tools import (
    append_to_note_payload,
    attachment_extract_parts,
    list_due_notes_payload,
    list_notes_payload,
    mark_note_done_payload,
    mark_note_resurfaced_payload,
    read_chat_attachment_payload,
    read_note_attachment_payload,
    read_note_payload,
    refresh_attachment_extracts,
    resolve_style_reference,
    style_prompt_from_reference,
)
from vesnai.ai.selftune import ResurfacingScheduler
from vesnai.ai.tool_schemas import tool_by_name
from vesnai.notes import NoteInput, NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.providers.base import ChatMessage, ToolCall, VisionProvider
from vesnai.providers.fakes import (
    FakeAIProvider,
    FakeEmbeddingProvider,
    FakeVisionProvider,
)


def test_read_note_returns_body_and_attachments(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/style.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    path, _ = notes.create(
        NoteInput(
            title="marena",
            body="watercolor style reference",
            type="Photo",
            attachments=[att],
            links=["notes/other.md"],
        )
    )
    out = read_note_payload(notes, path)
    assert out["title"] == "marena"
    assert "watercolor" in out["body"]
    assert att in out["attachments"]
    assert "notes/other.md" in out["links"]


def test_read_note_attachment_vision(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/style.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    path, _ = notes.create(
        NoteInput(title="marena", body="", type="Photo", attachments=[att])
    )
    out = read_note_attachment_payload(
        notes, note_path=path, vision=FakeVisionProvider()
    )
    assert "description" in out
    assert "[fake-caption" in out["description"]


def test_list_notes_filters_type(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    notes.create(NoteInput(title="T1", body="", type="Task"))
    notes.create(NoteInput(title="I1", body="", type="Idea"))
    out = list_notes_payload(notes, note_type="Task")
    assert len(out["notes"]) == 1
    assert out["notes"][0]["type"] == "Task"


def test_style_prompt_from_note_with_image(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/x.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    path, _ = notes.create(
        NoteInput(title="ref", body="", type="Photo", attachments=[att])
    )
    clause = style_prompt_from_reference(notes, path, FakeVisionProvider())
    assert clause is not None
    assert "Visual style reference" in clause


def test_chat_dispatch_read_and_update_note(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FakeEmbeddingProvider())
    path, _ = notes.create(NoteInput(title="Old", body="body", type="Note"))
    index.index_concept(path, notes.get(path))
    chat = ChatService(FakeAIProvider(), index, notes)
    read = chat._dispatch("read_note", {"path": path}, pending_jobs=[])
    assert read["title"] == "Old"
    updated = chat._dispatch(
        "update_note",
        {"path": path, "type": "Task", "title": "New"},
        pending_jobs=[],
    )
    assert updated["updated"] == path
    assert notes.get(path).type == "Task"
    assert notes.get(path).title == "New"


def test_chat_delete_note(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FakeEmbeddingProvider())
    path, _ = notes.create(NoteInput(title="X", body=""))
    index.index_concept(path, notes.get(path))
    chat = ChatService(FakeAIProvider(), index, notes)
    out = chat._dispatch("delete_note", {"path": path}, pending_jobs=[])
    assert out["deleted"] == path
    assert not store.exists(path)


def test_note_access_rules_in_system_prompt():
    content = build_system_content(rag="(none)", memory_block="", language="en")
    assert "NEVER say you do not have access" in content
    assert NOTE_ACCESS_RULES.split("\n")[0] in content
    assert "style_reference_path" in content
    assert "Tool routing policy" in content
    assert "LLM-driven via Ollama tool_calls" in content


def test_new_tool_schemas_registered():
    for name in (
        "read_note",
        "read_note_attachment",
        "list_notes",
        "get_note_links",
        "update_note",
        "delete_note",
        "unlink_notes",
        "enrich_note",
        "list_due_notes",
        "mark_note_resurfaced",
        "mark_note_done",
        "append_to_note",
        "read_chat_attachment",
    ):
        assert tool_by_name(name) is not None
    gen = tool_by_name("generate_image")
    assert gen is not None
    assert "style_reference_path" in gen.parameters["properties"]


def test_mark_note_resurfaced_payload(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    path, _ = notes.create(NoteInput(title="Due", body=""))
    out = mark_note_resurfaced_payload(notes, path, clock=fake_clock)
    assert out["path"] == path
    assert out["resurface_count"] == 1
    assert notes.get(path).vesnai["last_resurfaced"]


def test_mark_note_done_payload_and_reopen(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    path, _ = notes.create(NoteInput(title="Shopping", body="milk"))
    out = mark_note_done_payload(notes, path)
    assert out["done"] is True
    assert out["done_at"]
    assert notes.get(path).done is True
    reopened = mark_note_done_payload(notes, path, done=False)
    assert reopened["done"] is False
    assert reopened["done_at"] is None
    assert notes.get(path).done is False


def test_chat_dispatch_mark_note_done(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FakeEmbeddingProvider())
    path, _ = notes.create(NoteInput(title="Task", body="do it"))
    index.index_concept(path, notes.get(path))
    chat = ChatService(FakeAIProvider(), index, notes)
    # done defaults to true when omitted.
    out = chat._dispatch("mark_note_done", {"path": path}, pending_jobs=[])
    assert out["done"] is True
    assert notes.get(path).done is True
    out = chat._dispatch("mark_note_done", {"path": path, "done": False}, pending_jobs=[])
    assert out["done"] is False


def test_append_to_note_preserves_body(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    path, _ = notes.create(NoteInput(title="Log", body="First line"))
    out = append_to_note_payload(notes, path, "Second line")
    assert out["updated"] == path
    assert "First line" in notes.get(path).body
    assert "Second line" in notes.get(path).body


def test_attachment_extracts_indexed(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/scan.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    path, concept = notes.create(
        NoteInput(title="Photo note", body="", type="Photo", attachments=[att])
    )
    concept = refresh_attachment_extracts(
        notes, path, concept, vision=FakeVisionProvider()
    )
    parts = attachment_extract_parts(concept)
    assert parts and "[fake-caption" in parts[0]
    index = IndexService(FakeEmbeddingProvider())
    index.index_concept(path, concept)
    hits = index.search("fake-caption", top_k=3)
    assert any(h.payload.get("path") == path for h in hits)


def test_read_chat_attachment_payload(tmp_path, fake_clock):
    conv_dir = tmp_path / "convos"
    convos = ConversationStore(conv_dir, clock=fake_clock)
    convo = convos.create("Hello")
    meta = convos.save_attachment(convo.id, "photo.png", b"\x89PNG\r\n\x1a\nfake", kind="image")
    _, msg_id = convos.append(
        convo.id,
        "user",
        "see this",
        attachments=[meta],
        message_id="msg-1",
    )

    def read_att(session_id: str, name: str) -> bytes:
        return convos.read_attachment(session_id, name)

    out = read_chat_attachment_payload(
        get_conversation=convos.get,
        read_attachment=read_att,
        session_id=convo.id,
        attachment_path=meta["path"],
        message_id=msg_id,
        vision=FakeVisionProvider(),
    )
    assert "description" in out
    assert "[fake-caption" in out["description"]


def test_chat_dispatch_mark_and_append(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FakeEmbeddingProvider())
    path, _ = notes.create(NoteInput(title="N", body="start"))
    index.index_concept(path, notes.get(path))
    chat = ChatService(FakeAIProvider(), index, notes, vision_provider=FakeVisionProvider())
    marked = chat._dispatch("mark_note_resurfaced", {"path": path}, pending_jobs=[])
    assert marked["resurface_count"] == 1
    appended = chat._dispatch(
        "append_to_note",
        {"path": path, "text": "more"},
        pending_jobs=[],
    )
    assert appended["updated"] == path
    assert "more" in notes.get(path).body


def test_list_due_notes_payload(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    path, concept = notes.create(NoteInput(title="Review me", body=""))
    concept.vesnai["created"] = "2000-01-01T00:00:00+00:00"
    store.write_concept(path, concept, message="backdate")
    sched = ResurfacingScheduler(clock=fake_clock)
    out = list_due_notes_payload(notes, sched)
    assert any(n["path"] == path for n in out["due_notes"])


class BrokenVision(VisionProvider):
    def caption(self, data: bytes, prompt: str) -> str:
        raise RuntimeError("ollama down")


def test_read_note_attachment_vision_failure(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/style.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    path, _ = notes.create(
        NoteInput(title="marena", body="", type="Photo", attachments=[att])
    )
    out = read_note_attachment_payload(
        notes, note_path=path, vision=BrokenVision()
    )
    assert "error" in out
    assert "vision failed" in out["error"]


def test_style_reference_uses_cached_extract(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/style.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    path, concept = notes.create(
        NoteInput(title="ref", body="", type="Photo", attachments=[att])
    )
    concept.vesnai["attachment_extracts"] = {att: "cached watercolor style"}
    store.write_concept(path, concept, message="test")
    out = resolve_style_reference(notes, path, BrokenVision())
    assert out["clause"] == "Visual style reference: cached watercolor style"


def test_generate_image_style_reference_vision_error(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FakeEmbeddingProvider())
    att = "attachments/style.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    path, _ = notes.create(
        NoteInput(title="marena", body="", type="Photo", attachments=[att])
    )
    jobs: list[str] = []

    def submit(prompt, sid, mid, save):
        jobs.append(prompt)
        return "job-1"

    chat = ChatService(
        FakeAIProvider(),
        index,
        notes,
        vision_provider=BrokenVision(),
        submit_image_job=submit,
    )
    out = chat._dispatch(
        "generate_image",
        {"prompt": "portrait", "style_reference_path": path},
        pending_jobs=[],
        session_id="s1",
        assistant_message_id="a1",
    )
    assert out["status"] == "queued"
    assert jobs
    assert "Inspired by note titled: marena" in jobs[0]


def test_style_reference_attachment_path_no_crash(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/style.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    path, concept = notes.create(
        NoteInput(title="marena", body="", type="Photo", attachments=[att])
    )
    concept.vesnai["attachment_extracts"] = {att: "watercolor marena style"}
    store.write_concept(path, concept, message="test")
    out = resolve_style_reference(notes, att, BrokenVision())
    assert out["clause"] == "Visual style reference: watercolor marena style"


def test_read_note_rejects_attachment_path(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/style.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    out = read_note_payload(notes, att)
    assert out["error"] == "not a note path; use read_note_attachment"
    assert out["path"] == att


def test_resolve_attachment_bare_filename(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/style.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    path, _ = notes.create(
        NoteInput(title="marena", body="", type="Photo", attachments=[att])
    )
    out = read_note_attachment_payload(
        notes,
        note_path=path,
        attachment_path="style.png",
        vision=FakeVisionProvider(),
    )
    assert "description" in out
    assert out["attachment_path"] == att


def test_style_reference_uses_cache_without_note_path(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/style.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    path, concept = notes.create(
        NoteInput(title="ref", body="", type="Photo", attachments=[att])
    )
    concept.vesnai["attachment_extracts"] = {att: "cached from parent"}
    store.write_concept(path, concept, message="test")
    out = resolve_style_reference(notes, att, BrokenVision())
    assert out["clause"] == "Visual style reference: cached from parent"


def test_style_reference_vision_fallback_to_body(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/style.png"
    store.save_attachment(att, b"\x89PNG\r\n\x1a\nfake")
    path, _ = notes.create(
        NoteInput(
            title="marena",
            body="soft watercolor brush strokes",
            type="Photo",
            attachments=[att],
        )
    )
    jobs: list[str] = []

    def submit(prompt, sid, mid, save):
        jobs.append(prompt)
        return "job-1"

    chat = ChatService(
        FakeAIProvider(),
        IndexService(FakeEmbeddingProvider()),
        notes,
        vision_provider=BrokenVision(),
        submit_image_job=submit,
    )
    out = chat._dispatch(
        "generate_image",
        {"prompt": "portrait", "style_reference_path": path},
        pending_jobs=[],
        session_id="s1",
        assistant_message_id="a1",
    )
    assert out["status"] == "queued"
    assert "soft watercolor brush strokes" in jobs[0]


def test_dispatch_exception_returns_tool_error(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FakeEmbeddingProvider())
    chat = ChatService(
        FakeAIProvider(
            scripted=[
                ChatMessage(
                    role="assistant",
                    content="",
                    tool_calls=[ToolCall(name="read_note", arguments={"path": "x"})],
                ),
                ChatMessage(role="assistant", content="recovered"),
            ]
        ),
        index,
        notes,
    )

    def boom(*_args, **_kwargs):
        raise UnicodeDecodeError("utf-8", b"\x89", 0, 1, "invalid start byte")

    chat._dispatch = boom  # type: ignore[method-assign]
    turn = chat._run_tool_loop(
        [ChatMessage(role="user", content="hi")],
        session_id=None,
        assistant_message_id=None,
        pending_jobs=[],
        executed=[],
    )
    assert turn.tool_calls[0]["result"]["error"]
    assert "invalid start byte" in turn.tool_calls[0]["result"]["error"]
    assert turn.content == "recovered"
