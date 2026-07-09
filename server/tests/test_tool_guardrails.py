"""Tests for structural image guardrails (no intent regex)."""

from __future__ import annotations

from vesnai.ai.tool_guardrails import (
    has_external_image_markdown,
    needs_chat_image_job,
    resolve_retry_kind,
    sanitize_assistant_image_content,
    strip_external_image_markdown,
    structural_image_remediation_needed,
)
from vesnai.ai.turn_action_validator import TurnActionAudit

POLLINATIONS = (
    "Oto obrazek:\n"
    "![cat](https://image.pollinations.ai/prompt/cat?width=1024&height=1024)"
)


def test_structural_image_remediation_on_external_markdown():
    assert structural_image_remediation_needed(
        "![x](https://example.com/a.png)",
        [],
    )


def test_no_structural_remediation_when_generate_image_queued():
    executed = [
        {"tool": "generate_image", "result": {"status": "queued", "job_id": "j1"}}
    ]
    assert not structural_image_remediation_needed(POLLINATIONS, executed)


def test_resolve_retry_kind_uses_llm_audit():
    audit = TurnActionAudit(missing_actions=["web_search"], source="llm")
    assert resolve_retry_kind(
        audit=audit,
        assistant_content="No search done.",
        executed=[],
    ) == "web_search"


def test_resolve_retry_kind_skips_when_llm_audit_clear():
    audit = TurnActionAudit(missing_actions=[], source="llm")
    assert resolve_retry_kind(
        audit=audit,
        assistant_content="Here is info.",
        executed=[],
    ) is None


def test_resolve_retry_kind_structural_image_without_audit():
    assert resolve_retry_kind(
        audit=None,
        assistant_content="![x](sandbox:/mnt/data/image.png)",
        executed=[],
    ) == "image"


def test_needs_chat_image_job_from_audit():
    audit = TurnActionAudit(missing_actions=["generate_image"], source="llm")
    assert needs_chat_image_job("reply", [], audit=audit)


def test_needs_chat_image_job_structural_only():
    assert needs_chat_image_job(
        "![x](https://cdn.example/img.png)",
        [],
        audit=None,
    )


def test_strip_fake_image_markdown():
    from vesnai.ai.tool_guardrails import strip_fake_image_markdown

    text = "Oto:\n![x](sandbox:/mnt/data/image.png)"
    cleaned = strip_fake_image_markdown(text)
    assert "sandbox:" not in cleaned
    assert "Oto:" in cleaned


def test_strip_external_image_markdown_keeps_intro_text():
    text = "Intro line.\n" + POLLINATIONS.split("\n", 1)[1]
    cleaned = strip_external_image_markdown(text)
    assert "Intro line." in cleaned
    assert "pollinations" not in cleaned.lower()


def test_strip_does_not_remove_text_links():
    text = "See [Wikipedia](https://en.wikipedia.org/wiki/Cat) for more."
    assert strip_external_image_markdown(text) == text


def test_has_external_image_markdown_detects_any_host():
    assert has_external_image_markdown("![a](https://cdn.example/img.png)")


def test_sanitize_strips_url_when_generate_image_queued():
    executed = [
        {"tool": "generate_image", "result": {"status": "queued", "job_id": "j1"}}
    ]
    result = sanitize_assistant_image_content(POLLINATIONS, executed)
    assert "pollinations" not in result.lower()
    assert "Oto obrazek" in result


def test_sanitize_keeps_url_when_no_tool_for_ingest():
    result = sanitize_assistant_image_content(POLLINATIONS, [])
    assert "pollinations" in result.lower()


def test_extract_external_image_urls():
    from vesnai.ai.tool_guardrails import extract_external_image_urls

    urls = extract_external_image_urls(POLLINATIONS)
    assert len(urls) == 1
    assert urls[0].startswith("https://image.pollinations.ai/")
