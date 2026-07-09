"""Semantic post-turn action validation."""

from __future__ import annotations

from unittest.mock import MagicMock

from vesnai.ai.chat import ChatService
from vesnai.ai.tool_guardrails import needs_chat_image_job
from vesnai.ai.turn_action_validator import TurnActionAudit, TurnActionValidator
from vesnai.providers.fakes import FakeAIProvider


class _ImageAuditFake(FakeAIProvider):
    def complete(self, prompt: str, *, temperature: float = 0.2, think: bool = False) -> str:
        return (
            '{"claims": [{"action": "generate_image", "epistemic_source": "ungrounded"}], '
            '"missing_actions": ["generate_image"], "user_intents": ["draw an image"], '
            '"confidence": 0.9}'
        )


class _NoImageAuditFake(FakeAIProvider):
    def complete(self, prompt: str, *, temperature: float = 0.2, think: bool = False) -> str:
        return (
            '{"claims": [], "missing_actions": [], "user_intents": ["summarize notes"], '
            '"confidence": 0.8}'
        )


class _WebSearchAuditFake(FakeAIProvider):
    def complete_structured(self, prompt, schema, *, temperature=0.2, think=False):
        return (
            '{"claims": [{"action": "web_search", "epistemic_source": "ungrounded"}], '
            '"missing_actions": ["web_search"], '
            '"user_intents": ["restaurants nearby"], "confidence": 0.92}'
        )


class _NoteAttachAuditFake(FakeAIProvider):
    def complete_structured(self, prompt, schema, *, temperature=0.2, think=False):
        return (
            '{"claims": [], "missing_actions": ["read_note_attachment"], '
            '"user_intents": ["style from note photo"], "confidence": 0.88}'
        )


class _ParseFailThenOkFake(FakeAIProvider):
    def __init__(self) -> None:
        super().__init__()
        self._calls = 0

    def complete_structured(self, prompt, schema, *, temperature=0.2, think=False):
        self._calls += 1
        if self._calls == 1:
            return "not json"
        return (
            '{"claims": [], "missing_actions": ["web_search"], '
            '"user_intents": ["weather"], "confidence": 0.9}'
        )


def test_validator_parses_missing_generate_image():
    audit = TurnActionValidator(_ImageAuditFake()).audit(
        user_message="draw me a cat",
        assistant_content="Here is your image, generating now.",
        executed=[],
    )
    assert audit.source == "llm"
    assert audit.needs_image_job()


def test_validator_reconciles_successful_tool():
    audit = TurnActionValidator(_ImageAuditFake()).audit(
        user_message="draw me a cat",
        assistant_content="Generating.",
        executed=[{"tool": "generate_image", "result": {"status": "queued", "job_id": "j1"}}],
    )
    assert audit.missing_actions == []


def test_validator_primary_retry_kind():
    audit = TurnActionAudit(
        missing_actions=["update_memory"],
        source="llm",
    )
    assert audit.primary_retry_kind() == "memory"
    audit = TurnActionAudit(
        user_wanted_image=True,
        assistant_claimed_image=True,
        missing_actions=["generate_image"],
        source="llm",
    )
    assert needs_chat_image_job(
        "totally unrelated assistant text",
        [],
        audit=audit,
    )


def test_chat_force_queue_via_llm_audit_not_regex():
    submitted: list[tuple] = []

    def submit_image_job(prompt, session_id, message_id, save_to_notes):
        submitted.append((prompt, session_id, message_id, save_to_notes))
        return "job-llm"

    chat = ChatService(
        ai=MagicMock(),
        notes=MagicMock(),
        index=MagicMock(),
        submit_image_job=submit_image_job,
        turn_action_validator=TurnActionValidator(_ImageAuditFake()),
    )
    chat._run_tool_loop = MagicMock(  # type: ignore[method-assign]
        return_value=MagicMock(
            content="Your portrait is being prepared.",
            tool_calls=[],
            pending_jobs=[],
        )
    )

    turn = chat.run(
        "unusual phrasing without image keywords",
        language="en",
        session_id="sess-1",
        assistant_message_id="msg-1",
    )

    assert submitted
    assert any(t.get("tool") == "generate_image" for t in turn.tool_calls)


def test_chat_skips_force_queue_when_audit_clear():
    submitted: list[tuple] = []

    def submit_image_job(prompt, session_id, message_id, save_to_notes):
        submitted.append((prompt, session_id, message_id, save_to_notes))
        return "job-none"

    chat = ChatService(
        ai=MagicMock(),
        notes=MagicMock(),
        index=MagicMock(),
        submit_image_job=submit_image_job,
        turn_action_validator=TurnActionValidator(_NoImageAuditFake()),
    )
    chat._run_tool_loop = MagicMock(  # type: ignore[method-assign]
        return_value=MagicMock(
            content="Sure, here is a summary of your notes.",
            tool_calls=[],
            pending_jobs=[],
        )
    )

    chat.run(
        "summarize my notes",
        language="en",
        session_id="sess-1",
        assistant_message_id="msg-1",
    )

    assert submitted == []


def test_validator_flags_missing_web_search_for_local_request():
    audit = TurnActionValidator(_WebSearchAuditFake()).audit(
        user_message="możesz polecić restauracje w okolicy?",
        assistant_content="Niestety nie mam dostępu do aktualnych danych.",
        executed=[],
        location_label="Pabianice",
    )
    assert audit.source == "llm"
    assert audit.primary_retry_kind() == "web_search"


def test_validator_flags_missing_read_note_attachment():
    audit = TurnActionValidator(_NoteAttachAuditFake()).audit(
        user_message="wygeneruj mnie w stylu zdjęcia z notatki marena",
        assistant_content="Nie mam dostępu do tego zdjęcia z notatki.",
        executed=[],
    )
    assert audit.primary_retry_kind() == "note_attachment"


def test_validator_retries_audit_once_on_parse_failure():
    fake = _ParseFailThenOkFake()
    audit = TurnActionValidator(fake).audit(
        user_message="jaka pogoda?",
        assistant_content="Nie wiem.",
        executed=[],
    )
    assert fake._calls == 2
    assert audit.source == "llm"
    assert "web_search" in audit.missing_actions
