"""Tests for forced FLUX queue when the model skips generate_image."""

from __future__ import annotations

from unittest.mock import MagicMock

from vesnai.ai.chat import ChatService
from vesnai.ai.chat_media import ChatAttachment
from vesnai.ai.turn_action_validator import TurnActionValidator
from vesnai.providers.fakes import FakeAIProvider


class _ImageAuditFake(FakeAIProvider):
    def complete(self, prompt: str, *, temperature: float = 0.2, think: bool = False) -> str:
        return (
            '{"claims": [{"action": "generate_image", "epistemic_source": "ungrounded"}], '
            '"missing_actions": ["generate_image"], "user_intents": ["draw an image"], '
            '"confidence": 0.9}'
        )


def test_force_queue_image_job_when_model_skips_tool():
    submitted: list[tuple] = []

    def submit_image_job(prompt, session_id, message_id, save_to_notes):
        submitted.append((prompt, session_id, message_id, save_to_notes))
        return "job-1"

    chat = ChatService(
        ai=MagicMock(),
        notes=MagicMock(),
        index=MagicMock(),
        submit_image_job=submit_image_job,
        turn_action_validator=TurnActionValidator(_ImageAuditFake()),
    )
    chat._run_tool_loop = MagicMock(  # type: ignore[method-assign]
        return_value=MagicMock(
            content="Generuję dla Ciebie obrazek…",
            tool_calls=[],
            pending_jobs=[],
        )
    )

    turn = chat.run(
        "wygeneruj mi obrazek kota",
        language="pl",
        session_id="sess-1",
        assistant_message_id="msg-1",
    )

    assert submitted == [("wygeneruj mi obrazek kota", "sess-1", "msg-1", False)]
    assert any(
        t.get("tool") == "generate_image"
        and (t.get("result") or {}).get("status") == "queued"
        for t in turn.tool_calls
    )
    assert any(j.get("kind") == "chat_generate_image" for j in (turn.pending_jobs or []))


def test_force_queue_when_polish_style_portrait_without_obraz_word():
    submitted: list[tuple] = []

    def submit_image_job(prompt, session_id, message_id, save_to_notes):
        submitted.append((prompt, session_id, message_id, save_to_notes))
        return "job-2"

    chat = ChatService(
        ai=MagicMock(),
        notes=MagicMock(),
        index=MagicMock(),
        submit_image_job=submit_image_job,
        turn_action_validator=TurnActionValidator(_ImageAuditFake()),
    )
    chat._run_tool_loop = MagicMock(  # type: ignore[method-assign]
        return_value=MagicMock(
            content=(
                "Oczywiście! Wygenerowałam wariację Twojego zdjęcia w stylu VesnAI. "
                "Obrazek jest generowany i pojawi się w czacie wkrótce!"
            ),
            tool_calls=[],
            pending_jobs=[],
        )
    )

    turn = chat.run(
        "to jest moje zdjęcie. czy możesz wygenerować mnie w swoim stylu?",
        language="pl",
        session_id="sess-1",
        assistant_message_id="msg-1",
        attachments=[ChatAttachment(path="x.jpg", kind="image", filename="x.jpg")],
    )

    assert submitted
    assert submitted[0][0]
    assert "uploaded photo" in submitted[0][0]
    assert any(
        t.get("tool") == "generate_image"
        and (t.get("result") or {}).get("status") == "queued"
        for t in turn.tool_calls
    )


def test_force_queue_strips_sandbox_image_markdown():
    submitted: list[tuple] = []

    def submit_image_job(prompt, session_id, message_id, save_to_notes):
        submitted.append((prompt, session_id, message_id, save_to_notes))
        return "job-3"

    chat = ChatService(
        ai=MagicMock(),
        notes=MagicMock(),
        index=MagicMock(),
        submit_image_job=submit_image_job,
    )
    chat._run_tool_loop = MagicMock(  # type: ignore[method-assign]
        return_value=MagicMock(
            content="Oto obrazek:\n![x](sandbox:/mnt/data/image.png)",
            tool_calls=[],
            pending_jobs=[],
        )
    )

    turn = chat.run(
        "spróbuj jeszcze raz wygenerować obrazek",
        language="pl",
        session_id="sess-1",
        assistant_message_id="msg-1",
    )

    assert submitted
    assert "sandbox:" not in turn.content.lower()
    assert any(t.get("tool") == "generate_image" for t in turn.tool_calls)
