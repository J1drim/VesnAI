"""Semantic post-turn validation: did required tools run for this reply?"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from typing import Literal

from pydantic import BaseModel, Field

from vesnai.ai.tool_guardrails import _tool_succeeded
from vesnai.ai.tool_receipts import TurnReceiptBatch
from vesnai.providers.base import AIProvider

log = logging.getLogger(__name__)

AuditedAction = Literal[
    "generate_image",
    "web_search",
    "create_note",
    "update_memory",
    "read_note_attachment",
]

KNOWN_ACTIONS = frozenset(
    {
        "generate_image",
        "web_search",
        "create_note",
        "update_memory",
        "read_note_attachment",
    }
)

ACTION_TO_RETRY_KIND = {
    "generate_image": "image",
    "web_search": "web_search",
    "create_note": "note",
    "update_memory": "memory",
    "read_note_attachment": "note_attachment",
}


class ClaimOut(BaseModel):
    action: str
    epistemic_source: Literal["tool", "inference", "ungrounded"] = "ungrounded"


class TurnActionAuditOut(BaseModel):
    claims: list[ClaimOut] = Field(default_factory=list)
    missing_actions: list[AuditedAction] = Field(default_factory=list)
    user_intents: list[str] = Field(default_factory=list)
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)


@dataclass
class TurnActionAudit:
    """Result of auditing one chat turn."""

    user_wanted_image: bool = False
    assistant_claimed_image: bool = False
    missing_actions: list[str] = field(default_factory=list)
    user_intents: list[str] = field(default_factory=list)
    confidence: float = 0.0
    claims: list[dict] = field(default_factory=list)
    source: str = "none"  # none | llm | error

    def needs_image_job(self) -> bool:
        return "generate_image" in self.missing_actions

    def primary_retry_kind(self) -> str | None:
        for action in (
            "update_memory",
            "create_note",
            "web_search",
            "read_note_attachment",
            "generate_image",
        ):
            if action in self.missing_actions:
                return ACTION_TO_RETRY_KIND[action]
        return None

    def to_trajectory_dict(self) -> dict:
        return {
            "missing_actions": self.missing_actions,
            "user_intents": self.user_intents,
            "confidence": self.confidence,
            "source": self.source,
            "claims": self.claims,
        }


def _summarize_tools(executed: list[dict], receipts: TurnReceiptBatch | None) -> str:
    if receipts is not None and receipts.receipts:
        return receipts.summarize()
    if not executed:
        return "(none)"
    lines: list[str] = []
    for entry in executed:
        tool = entry.get("tool", "?")
        result = entry.get("result")
        if isinstance(result, dict) and result.get("error"):
            lines.append(f"- {tool}: error={result.get('error')}")
        elif tool == "generate_image" and isinstance(result, dict):
            lines.append(f"- {tool}: status={result.get('status')}")
        elif isinstance(result, dict) and result.get("created"):
            lines.append(f"- {tool}: created={result.get('created')}")
        elif isinstance(result, dict) and result.get("success") is True:
            lines.append(f"- {tool}: success")
        else:
            lines.append(f"- {tool}: ok")
    return "\n".join(lines)


def _from_structured(data: TurnActionAuditOut) -> TurnActionAudit:
    missing: list[str] = [a for a in data.missing_actions if a in KNOWN_ACTIONS]
    claims = [c.model_dump() for c in data.claims]
    user_wanted_image = "generate_image" in missing or any(
        "image" in i.lower() or "obraz" in i.lower() for i in data.user_intents
    )
    assistant_claimed_image = any(
        c.action == "generate_image" and c.epistemic_source != "tool" for c in data.claims
    ) or any(c.action == "generate_image" for c in data.claims)
    return TurnActionAudit(
        user_wanted_image=user_wanted_image,
        assistant_claimed_image=assistant_claimed_image,
        missing_actions=missing,
        user_intents=list(data.user_intents),
        confidence=data.confidence,
        claims=claims,
        source="llm",
    )


def _parse_audit_json(raw: str) -> TurnActionAudit | None:
    text = raw.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
    try:
        data = json.loads(text)
        parsed = TurnActionAuditOut.model_validate(data)
        return _from_structured(parsed)
    except (json.JSONDecodeError, ValueError):
        return None


def _complete_structured(ai: AIProvider, prompt: str) -> str:
    if hasattr(ai, "complete_structured"):
        return ai.complete_structured(
            prompt,
            TurnActionAuditOut.model_json_schema(),
            temperature=0.0,
            think=True,
        )
    return ai.complete(prompt, temperature=0.0, think=True)


def _build_audit_prompt(
    *,
    user_message: str,
    assistant_content: str,
    executed: list[dict],
    had_image_attachment: bool,
    location_label: str | None,
    receipts: TurnReceiptBatch | None,
) -> str:
    loc = location_label or "(none)"
    return (
        "You audit a personal assistant chat turn. Return JSON matching the schema.\n"
        "missing_actions: subset of generate_image, web_search, create_note, update_memory, "
        "read_note_attachment that the user clearly wanted OR the assistant clearly claimed "
        "to have done, but which did NOT succeed per tool receipts.\n"
        "claims: each assistant claim about an action with epistemic_source "
        "(tool=backed by receipt, inference=reasonable guess, ungrounded=hallucination).\n"
        "user_intents: short free-form descriptions of what the user wanted (any language).\n"
        "Rules:\n"
        "- Local recommendations, restaurants, weather, prices, current events → web_search.\n"
        "- If the assistant says it has no access to current/external data without a successful "
        "web_search receipt → list web_search.\n"
        "- User wants image in style of a note photo without read_note_attachment or "
        "generate_image(style_reference_path) → list read_note_attachment and/or generate_image.\n"
        "- If generate_image receipt status is queued or succeeded, do NOT list generate_image.\n"
        "- If read_note_attachment returned description or text, do NOT list read_note_attachment.\n"
        "- Fake image markdown in the reply counts as ungrounded generate_image claim.\n"
        "- Memory/note save claims without matching tool receipts → update_memory / create_note.\n"
        "- If the user only wanted text, missing_actions must be empty.\n"
        f"- User attached a photo this turn: {had_image_attachment}\n"
        f"- Shared location label: {loc}\n\n"
        f"User message:\n{user_message[:1500]}\n\n"
        f"Assistant reply:\n{assistant_content[:2000]}\n\n"
        f"Tool receipts:\n{_summarize_tools(executed, receipts)}"
    )


class TurnActionValidator:
    """LLM audit after a chat turn (uses reasoning model, thinking on)."""

    def __init__(self, ai: AIProvider | None) -> None:
        self._ai = ai

    def _run_audit(
        self,
        *,
        user_message: str,
        assistant_content: str,
        executed: list[dict],
        had_image_attachment: bool,
        location_label: str | None,
        receipts: TurnReceiptBatch | None,
    ) -> TurnActionAudit | None:
        prompt = _build_audit_prompt(
            user_message=user_message,
            assistant_content=assistant_content,
            executed=executed,
            had_image_attachment=had_image_attachment,
            location_label=location_label,
            receipts=receipts,
        )
        raw = _complete_structured(self._ai, prompt)  # type: ignore[arg-type]
        parsed = _parse_audit_json(raw)
        if parsed is None:
            log.warning("turn_action_validator_parse_failed", extra={"raw": raw[:200]})
            return None
        missing = [
            a for a in parsed.missing_actions if not _tool_succeeded(executed, {a})
        ]
        parsed.missing_actions = missing
        return parsed

    def audit(
        self,
        *,
        user_message: str,
        assistant_content: str,
        executed: list[dict],
        had_image_attachment: bool = False,
        location_label: str | None = None,
        receipts: TurnReceiptBatch | None = None,
    ) -> TurnActionAudit:
        if self._ai is None:
            return TurnActionAudit()
        try:
            parsed = self._run_audit(
                user_message=user_message,
                assistant_content=assistant_content,
                executed=executed,
                had_image_attachment=had_image_attachment,
                location_label=location_label,
                receipts=receipts,
            )
            if parsed is None:
                parsed = self._run_audit(
                    user_message=user_message,
                    assistant_content=assistant_content,
                    executed=executed,
                    had_image_attachment=had_image_attachment,
                    location_label=location_label,
                    receipts=receipts,
                )
            if parsed is None:
                return TurnActionAudit(source="error")
            return parsed
        except Exception:
            log.exception("turn_action_validator_failed")
            return TurnActionAudit(source="error")
