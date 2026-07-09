"""Idle-time trajectory review that evolves injectable tool policy bullets."""

from __future__ import annotations

import json
import logging
from pathlib import Path

from vesnai.ai.selftune import TrajectoryLog
from vesnai.providers.base import AIProvider, Clock, SystemClock

log = logging.getLogger(__name__)

REVIEW_PROMPT = (
    "Review recent assistant chat trajectories for recurring tool-use failures "
    "(claimed action without tool, wrong tool, skipped generate_image, etc.). "
    "Reply with JSON only: {\"bullets\": string[]}. "
    "Each bullet is one concise rule for the system prompt (max 120 chars). "
    "Return empty bullets if nothing actionable. Do not repeat generic advice."
)


class ToolPolicyStore:
    def __init__(self, data_dir: Path | str) -> None:
        self._path = Path(data_dir) / "tool_policy.md"
        self._path.parent.mkdir(parents=True, exist_ok=True)

    def read(self) -> str:
        if not self._path.exists():
            return ""
        return self._path.read_text(encoding="utf-8").strip()

    def write(self, content: str) -> None:
        self._path.write_text(content.strip() + "\n", encoding="utf-8")

    def append_bullets(self, bullets: list[str], *, max_bullets: int = 20) -> None:
        existing = [ln.strip()[2:] for ln in self.read().splitlines() if ln.strip().startswith("- ")]
        merged: list[str] = []
        for b in [*existing, *bullets]:
            b = b.strip()
            if b and b not in merged:
                merged.append(b)
        trimmed = merged[-max_bullets:]
        body = "\n".join(f"- {b}" for b in trimmed)
        self.write(body)


class ToolPolicyReviewAgent:
    def __init__(
        self,
        ai: AIProvider,
        trajectories: TrajectoryLog,
        policy: ToolPolicyStore,
        *,
        min_failures: int = 3,
        clock: Clock | None = None,
    ) -> None:
        self.ai = ai
        self.trajectories = trajectories
        self.policy = policy
        self.min_failures = min_failures
        self.clock = clock or SystemClock()
        self._last_run_ts: float | None = None

    def _failure_candidates(self) -> list[dict]:
        out: list[dict] = []
        for traj in self.trajectories.all()[-200:]:
            audit = traj.get("audit") or {}
            missing = audit.get("missing_actions") or []
            if missing:
                out.append(traj)
                continue
            tools = {t.get("tool") for t in traj.get("tool_calls") or []}
            snippet = (traj.get("assistant_snippet") or "").lower()
            if "generuj" in snippet or "generated" in snippet or "obraz" in snippet:
                if "generate_image" not in tools:
                    out.append(traj)
        return out

    def should_run(self, *, interval_hours: float) -> bool:
        if self._last_run_ts is None:
            return True
        elapsed = self.clock.monotonic() - self._last_run_ts
        return elapsed >= interval_hours * 3600

    def run_if_due(self, *, interval_hours: float = 24) -> bool:
        if not self.should_run(interval_hours=interval_hours):
            return False
        candidates = self._failure_candidates()
        if len(candidates) < self.min_failures:
            self._last_run_ts = self.clock.monotonic()
            return False
        sample = candidates[-15:]
        payload = json.dumps(
            [
                {
                    "message": t.get("message"),
                    "tools": [x.get("tool") for x in t.get("tool_calls") or []],
                    "assistant": t.get("assistant_snippet"),
                    "audit": t.get("audit"),
                }
                for t in sample
            ],
            ensure_ascii=False,
        )[:8000]
        prompt = f"{REVIEW_PROMPT}\n\nTrajectories:\n{payload}"
        try:
            raw = self.ai.complete(prompt, temperature=0.0, think=True)
            bullets = _parse_bullets(raw)
            if bullets:
                self.policy.append_bullets(bullets)
                log.info("tool_policy_review_updated: %s bullets", len(bullets))
        except Exception:
            log.exception("tool_policy_review_failed")
        self._last_run_ts = self.clock.monotonic()
        return True


def _parse_bullets(raw: str) -> list[str]:
    text = raw.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return []
    if not isinstance(data, dict):
        return []
    bullets = data.get("bullets") or []
    if not isinstance(bullets, list):
        return []
    return [str(b).strip() for b in bullets if str(b).strip()]
