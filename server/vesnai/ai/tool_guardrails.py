"""Post-turn guardrails: structural checks + LLM audit retry (no intent regex).

Tool routing must stay LLM-driven (Ollama tool_calls). Do not add keyword-based
intent detection or hardcoded tool chains here — only structural safety nets and
optional LLM audit retries.
"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from vesnai.ai.turn_action_validator import TurnActionAudit

_EXTERNAL_IMAGE_MARKDOWN = re.compile(
    r"!\[[^\]]*\]\(\s*https?://[^)]+\)",
    re.IGNORECASE,
)
_FAKE_IMAGE_MARKDOWN = re.compile(
    r"!\[[^\]]*\]\(\s*(?:sandbox:|file:|/mnt/|/tmp/)[^)]+\)",
    re.IGNORECASE,
)
_EXTERNAL_IMAGE_URL = re.compile(
    r"!\[[^\]]*\]\(\s*(https?://[^)]+)\)",
    re.IGNORECASE,
)

TOOL_USE_ENFORCEMENT = (
    "Tool use enforcement:\n"
    "- You MUST call the appropriate tool before claiming an action succeeded.\n"
    "- Never end a turn with only a promise to act — execute tools in the same turn.\n"
    "- If a tool returns an error, explain honestly; do not pretend it succeeded."
)


def has_external_image_markdown(content: str) -> bool:
    return bool(_EXTERNAL_IMAGE_MARKDOWN.search(content))


def has_fake_image_markdown(content: str) -> bool:
    return bool(_FAKE_IMAGE_MARKDOWN.search(content))


def strip_fake_image_markdown(content: str) -> str:
    stripped = _FAKE_IMAGE_MARKDOWN.sub("", content)
    return re.sub(r"\n{3,}", "\n\n", stripped).strip()


def extract_external_image_urls(content: str) -> list[str]:
    return _EXTERNAL_IMAGE_URL.findall(content)


def strip_external_image_markdown(content: str) -> str:
    stripped = _EXTERNAL_IMAGE_MARKDOWN.sub("", content)
    return re.sub(r"\n{3,}", "\n\n", stripped).strip()


def tool_succeeded(executed: list[dict], names: set[str]) -> bool:
    return _tool_succeeded(executed, names)


def _tool_succeeded(executed: list[dict], names: set[str]) -> bool:
    for entry in executed:
        if entry.get("tool") not in names:
            continue
        result = entry.get("result") or {}
        if not isinstance(result, dict):
            return True
        if result.get("success") is False or result.get("error"):
            continue
        if result.get("created") or result.get("success") is True:
            return True
        if entry.get("tool") == "update_memory" and result.get("path"):
            return True
        if entry.get("tool") in ("create_note", "propose_idea") and result.get("created"):
            return True
        if entry.get("tool") == "web_search" and (
            result.get("research_note_path") or result.get("summary")
        ):
            return True
        if entry.get("tool") == "generate_image" and result.get("status") == "queued":
            return True
        if entry.get("tool") == "read_note_attachment" and (
            result.get("description") or result.get("text")
        ):
            return True
    return False


def structural_image_remediation_needed(
    assistant_content: str,
    executed: list[dict],
) -> bool:
    """Deterministic: fake/external image markdown without a generate_image receipt."""
    if _tool_succeeded(executed, {"generate_image"}):
        return False
    return has_external_image_markdown(assistant_content) or has_fake_image_markdown(
        assistant_content
    )


def retry_kind_from_audit(audit: TurnActionAudit | None) -> str | None:
    if audit is None or audit.source != "llm":
        return None
    return audit.primary_retry_kind()


def resolve_retry_kind(
    *,
    audit: TurnActionAudit | None,
    assistant_content: str,
    executed: list[dict],
) -> str | None:
    llm_kind = retry_kind_from_audit(audit)
    if llm_kind:
        return llm_kind
    if structural_image_remediation_needed(assistant_content, executed):
        return "image"
    return None


def needs_chat_image_job(
    assistant_content: str,
    executed: list[dict],
    *,
    audit: TurnActionAudit | None = None,
) -> bool:
    """True when FLUX should be force-queued because generate_image did not run."""
    if audit is not None and audit.source == "llm" and audit.needs_image_job():
        return True
    return structural_image_remediation_needed(assistant_content, executed)


def sanitize_assistant_image_content(
    content: str,
    executed: list[dict],
    *,
    user_message: str = "",
    language: str | None = None,
) -> str:
    del user_message, language  # kept for call-site compatibility
    if has_fake_image_markdown(content):
        content = strip_fake_image_markdown(content)
    if not has_external_image_markdown(content):
        return content
    if _tool_succeeded(executed, {"generate_image"}):
        cleaned = strip_external_image_markdown(content)
        if cleaned:
            return cleaned
        return "Generuję obrazek lokalnie — pojawi się jako załącznik."
    return content


def corrective_system_message(kind: str) -> str:
    if kind == "memory":
        return (
            "You claimed to save to memory but update_memory did not succeed. "
            "Call update_memory with the correct target and entry, then reply briefly."
        )
    if kind == "web_search":
        return (
            "The user wanted current or external information but web_search did not succeed. "
            "Call web_search now (include location in query when relevant), then reply briefly."
        )
    if kind == "note_attachment":
        return (
            "The user referenced an image in a saved note but read_note_attachment did not "
            "succeed. Call search_notes/read_note to find the note, then read_note_attachment "
            "or generate_image with style_reference_path, then reply briefly."
        )
    if kind == "image":
        return (
            "You must call generate_image for chat images — never paste external image URLs "
            "(Pollinations or any ![...](http...) markdown). Call generate_image now with a "
            "descriptive prompt, then reply briefly without embedding image links."
        )
    return (
        "You claimed to save a note but no create_note or web_search tool succeeded. "
        "Call the appropriate tool now, then reply briefly."
    )
