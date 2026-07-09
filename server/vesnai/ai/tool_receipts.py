"""Ground-truth ledger of tool executions per chat turn (server-side only)."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from vesnai.providers.base import Clock, SystemClock


def _receipt_status(tool: str, result: dict | Any) -> str:
    if not isinstance(result, dict):
        return "succeeded"
    if result.get("error"):
        return "failed"
    if result.get("success") is False:
        return "failed"
    if tool == "generate_image" and result.get("status") == "queued":
        return "queued"
    if result.get("created") or result.get("success") is True:
        return "succeeded"
    if tool == "update_memory" and result.get("path"):
        return "succeeded"
    if tool == "web_search" and (result.get("research_note_path") or result.get("summary")):
        return "succeeded"
    if result.get("status") == "queued":
        return "queued"
    return "succeeded"


def _result_summary(tool: str, result: dict | Any) -> str:
    if not isinstance(result, dict):
        return str(result)[:120]
    if result.get("error"):
        return f"error={result.get('error')}"
    if tool == "generate_image":
        return f"status={result.get('status', '?')}"
    if result.get("created"):
        return f"created={result.get('created')}"
    if result.get("research_note_path"):
        return f"research_note={result.get('research_note_path')}"
    if result.get("success") is True:
        return "success"
    return "ok"


@dataclass
class ToolReceipt:
    turn_id: str
    tool: str
    arguments_hash: str
    status: str  # queued | succeeded | failed
    result_summary: str
    ts: str

    def to_dict(self) -> dict:
        return {
            "turn_id": self.turn_id,
            "tool": self.tool,
            "arguments_hash": self.arguments_hash,
            "status": self.status,
            "result_summary": self.result_summary,
            "ts": self.ts,
        }


@dataclass
class TurnReceiptBatch:
    turn_id: str
    receipts: list[ToolReceipt] = field(default_factory=list)

    def summarize(self) -> str:
        if not self.receipts:
            return "(none)"
        return "\n".join(
            f"- {r.tool}: {r.status} ({r.result_summary})" for r in self.receipts
        )

    def has_succeeded(self, tool: str) -> bool:
        return any(r.tool == tool and r.status in ("queued", "succeeded") for r in self.receipts)


def make_receipt(
    *,
    turn_id: str,
    tool: str,
    arguments: dict,
    result: dict | Any,
    ts: str,
) -> ToolReceipt:
    args_blob = json.dumps(arguments or {}, sort_keys=True, default=str)
    args_hash = hashlib.sha256(args_blob.encode()).hexdigest()[:16]
    status = _receipt_status(tool, result)
    return ToolReceipt(
        turn_id=turn_id,
        tool=tool,
        arguments_hash=args_hash,
        status=status,
        result_summary=_result_summary(tool, result),
        ts=ts,
    )


class ToolReceiptLedger:
    """Append-only per-session tool execution log."""

    def __init__(self, data_dir: Path | str, clock: Clock | None = None) -> None:
        self._dir = Path(data_dir) / "tool_receipts"
        self._dir.mkdir(parents=True, exist_ok=True)
        self.clock = clock or SystemClock()

    def _path(self, session_id: str) -> Path:
        return self._dir / f"{session_id}.jsonl"

    def append(self, session_id: str, receipt: ToolReceipt) -> None:
        with self._path(session_id).open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(receipt.to_dict()) + "\n")

    def for_turn(self, session_id: str, turn_id: str) -> TurnReceiptBatch:
        path = self._path(session_id)
        if not path.exists():
            return TurnReceiptBatch(turn_id=turn_id)
        receipts: list[ToolReceipt] = []
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            raw = json.loads(line)
            if raw.get("turn_id") != turn_id:
                continue
            receipts.append(
                ToolReceipt(
                    turn_id=raw["turn_id"],
                    tool=raw["tool"],
                    arguments_hash=raw.get("arguments_hash", ""),
                    status=raw.get("status", "succeeded"),
                    result_summary=raw.get("result_summary", ""),
                    ts=raw.get("ts", ""),
                )
            )
        return TurnReceiptBatch(turn_id=turn_id, receipts=receipts)

    def recent_for_session(self, session_id: str, limit: int = 50) -> list[dict]:
        path = self._path(session_id)
        if not path.exists():
            return []
        lines = [ln for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip()]
        return [json.loads(ln) for ln in lines[-limit:]]
