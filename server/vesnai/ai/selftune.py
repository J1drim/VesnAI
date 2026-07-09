"""Closed learning loop (Hermes-inspired) - all deterministic and testable.

Components:
- ``FeedbackStore``: captures tag accept/reject/add signals.
- ``TagClassifier``: a tiny retrainable token->tag model; ``evaluate`` reports
  accuracy so a retrain step can be shown to hold/improve a metric.
- ``ResurfacingScheduler``: spaced-repetition selection of due notes.
- ``MemoryConsolidator``: promotes durable facts into a linked OKF Memory note.
- ``SkillService``: stores/refines procedures as OKF ``Playbook`` concepts.
- ``UserModelService``: maintains an evolving user-profile concept.
- ``TrajectoryLog``: append + compress assistant trajectories for later training.
"""

from __future__ import annotations

import json
import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from vesnai.notes import NoteInput, NoteService
from vesnai.okf.model import Origin
from vesnai.providers.base import AIProvider, Clock, SystemClock

_WORD = re.compile(r"[a-zA-Z\u00c0-\u024f]+")


# --------------------------------------------------------------------------- #
# Feedback + tag classifier
# --------------------------------------------------------------------------- #
@dataclass
class FeedbackEvent:
    text: str
    tags: list[str]
    action: str = "accepted"  # accepted | rejected | added | removed


class FeedbackStore:
    def __init__(self, data_dir: Path) -> None:
        self._path = Path(data_dir) / "feedback.jsonl"
        self._path.parent.mkdir(parents=True, exist_ok=True)

    def record(self, event: FeedbackEvent) -> None:
        with self._path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(event.__dict__) + "\n")

    def all(self) -> list[FeedbackEvent]:
        if not self._path.exists():
            return []
        out = []
        for line in self._path.read_text().splitlines():
            if line.strip():
                d = json.loads(line)
                out.append(FeedbackEvent(**d))
        return out


class TagClassifier:
    """Token -> tag weight model. Deterministic; trained from labelled examples."""

    def __init__(self) -> None:
        self._weights: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
        self._tags: set[str] = set()

    @staticmethod
    def _tokens(text: str) -> list[str]:
        return [w.lower() for w in _WORD.findall(text)]

    def fit(self, examples: list[tuple[str, list[str]]]) -> None:
        self._weights.clear()
        self._tags.clear()
        for text, tags in examples:
            for tag in tags:
                self._tags.add(tag)
                for tok in set(self._tokens(text)):
                    self._weights[tok][tag] += 1.0

    def predict(self, text: str, top_k: int = 3) -> list[str]:
        scores: dict[str, float] = defaultdict(float)
        for tok in set(self._tokens(text)):
            for tag, w in self._weights.get(tok, {}).items():
                scores[tag] += w
        ranked = sorted(scores.items(), key=lambda kv: (-kv[1], kv[0]))
        return [tag for tag, _ in ranked[:top_k]]

    def evaluate(self, dataset: list[tuple[str, list[str]]]) -> float:
        if not dataset:
            return 0.0
        hits = 0
        for text, gold in dataset:
            pred = set(self.predict(text, top_k=max(1, len(gold))))
            if pred & set(gold):
                hits += 1
        return hits / len(dataset)

    @property
    def is_trained(self) -> bool:
        return bool(self._tags)


# --------------------------------------------------------------------------- #
# Spaced-repetition resurfacing
# --------------------------------------------------------------------------- #
# Increasing intervals (days) approximating spaced repetition.
RESURFACE_INTERVALS_DAYS = [1, 3, 7, 16, 35, 90]


class ResurfacingScheduler:
    def __init__(self, clock: Clock | None = None) -> None:
        self.clock = clock or SystemClock()

    def due(self, notes: dict[str, Any]) -> list[str]:
        """Return note paths whose next resurface time has passed.

        ``notes`` maps path -> concept. Uses ``vesnai.created`` and
        ``vesnai.resurface_count`` to compute the next due time.
        """
        now = self.clock.now()
        due: list[str] = []
        for path, concept in notes.items():
            if concept.vesnai.get("done"):
                # Done notes stay searchable for the assistant but are no
                # longer worth resurfacing for the user.
                continue
            created = _parse_dt(concept.vesnai.get("created"))
            if created is None:
                continue
            count = int(concept.vesnai.get("resurface_count", 0))
            idx = min(count, len(RESURFACE_INTERVALS_DAYS) - 1)
            interval = RESURFACE_INTERVALS_DAYS[idx]
            last = _parse_dt(concept.vesnai.get("last_resurfaced")) or created
            next_due = last.timestamp() + interval * 86400
            if now.timestamp() >= next_due:
                due.append(path)
        return sorted(due)


def _parse_dt(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value))
    except ValueError:
        return None


# --------------------------------------------------------------------------- #
# Durable memory store (Hermes-style split files)
# --------------------------------------------------------------------------- #
DEFAULT_MEMORY_DISK_MAX_CHARS = 100_000
DEFAULT_MEMORY_PROMPT_MAX_CHARS = 32_000

USER_MODEL_LEGACY_PATH = "profile/user-model.md"


@dataclass(frozen=True)
class MemoryTarget:
    path: str
    header: str
    title: str
    note_type: str = "Memory"


MEMORY_TARGETS: dict[str, MemoryTarget] = {
    "memory": MemoryTarget(
        "memory/memory.md",
        "Durable facts VesnAI chose to remember:",
        "Memory",
    ),
    "user": MemoryTarget(
        "memory/user.md",
        "User preferences and identity:",
        "User memory",
    ),
    "projects": MemoryTarget(
        "memory/projects.md",
        "Active projects and focus:",
        "Projects",
    ),
}


class DurableMemoryStore:
    """Multi-file durable memory (memory.md, user.md, projects.md)."""

    PATH = "memory/memory.md"

    def __init__(
        self,
        notes: NoteService,
        *,
        disk_max_chars: int = DEFAULT_MEMORY_DISK_MAX_CHARS,
        prompt_max_chars: int = DEFAULT_MEMORY_PROMPT_MAX_CHARS,
    ) -> None:
        self.notes = notes
        self.disk_max_chars = disk_max_chars
        self.prompt_max_chars = prompt_max_chars
        self.migrate()

    def migrate(self) -> None:
        """One-time bootstrap: user.md + import legacy UserModel attributes."""
        if not self.notes.store.exists(MEMORY_TARGETS["user"].path):
            self._write_target("user", MEMORY_TARGETS["user"].header, [])
        legacy = USER_MODEL_LEGACY_PATH
        if self.notes.store.exists(legacy):
            concept = self.notes.get(legacy)
            attrs = concept.vesnai.get("attributes") or {}
            if attrs:
                bullets = [f"- **{k}**: {v}" for k, v in sorted(attrs.items())]
                existing = self._read_bullets("user")
                merged = list(dict.fromkeys([*existing, *bullets]))
                spec = MEMORY_TARGETS["user"]
                self._write_target("user", spec.header, merged)

    @staticmethod
    def _normalize_bullet(entry: str) -> str:
        text = entry.strip()
        if text.startswith("- "):
            text = text[2:].strip()
        return text

    @staticmethod
    def _bullet_line(entry: str) -> str:
        return f"- {DurableMemoryStore._normalize_bullet(entry)}"

    def _read_bullets(self, target: str) -> list[str]:
        spec = MEMORY_TARGETS[target]
        if not self.notes.store.exists(spec.path):
            return []
        body = self.notes.get(spec.path).body
        return [
            line.rstrip()
            for line in body.splitlines()
            if line.strip().startswith("- ")
        ]

    def _body_for(self, target: str, bullets: list[str]) -> str:
        spec = MEMORY_TARGETS[target]
        if not bullets:
            return spec.header
        return spec.header + "\n\n" + "\n".join(bullets)

    def total_disk_chars(self) -> int:
        total = 0
        for key in MEMORY_TARGETS:
            spec = MEMORY_TARGETS[key]
            if self.notes.store.exists(spec.path):
                total += len(self.notes.get(spec.path).body)
        return total

    def _write_target(self, target: str, header: str, bullets: list[str]) -> str:
        spec = MEMORY_TARGETS[target]
        body = header if not bullets else header + "\n\n" + "\n".join(bullets)
        new_total = self.total_disk_chars()
        if self.notes.store.exists(spec.path):
            new_total -= len(self.notes.get(spec.path).body)
        new_total += len(body)
        if new_total > self.disk_max_chars:
            raise MemoryOverflowError(
                current_chars=new_total,
                limit=self.disk_max_chars,
                target=target,
            )
        if self.notes.store.exists(spec.path):
            concept = self.notes.get(spec.path)
            concept.body = body
            self.notes.store.write_concept(spec.path, concept, message=f"update {target} memory")
            return spec.path
        from vesnai.okf.model import Concept

        concept = Concept(
            frontmatter={
                "type": spec.note_type,
                "title": spec.title,
                "tags": ["generated", "memory"],
                "vesnai": {"origin": Origin.GENERATED.value, "links": []},
            },
            body=body,
        )
        self.notes.store.write_concept(spec.path, concept, message=f"create {target} memory")
        return spec.path

    def apply(
        self,
        action: str,
        target: str,
        entry: str,
        *,
        replace_match: str | None = None,
    ) -> dict:
        action = (action or "add").strip().lower()
        target = (target or "memory").strip().lower()
        if target not in MEMORY_TARGETS:
            return {"success": False, "error": f"unknown target {target!r}"}
        if action not in {"add", "replace", "remove"}:
            return {"success": False, "error": f"unknown action {action!r}"}
        bullets = self._read_bullets(target)
        spec = MEMORY_TARGETS[target]
        line = self._bullet_line(entry)
        norm_entry = self._normalize_bullet(entry)

        if action == "add":
            if line in bullets or any(self._normalize_bullet(b) == norm_entry for b in bullets):
                return {
                    "success": True,
                    "path": spec.path,
                    "action": action,
                    "duplicate": True,
                }
            bullets.append(line)
        elif action == "remove":
            match = (replace_match or norm_entry).strip().lower()
            bullets = [
                b
                for b in bullets
                if match not in self._normalize_bullet(b).lower()
                and match not in b.lower()
            ]
        else:  # replace
            match = (replace_match or norm_entry).strip().lower()
            replaced = False
            new_bullets: list[str] = []
            for b in bullets:
                if not replaced and (
                    match in self._normalize_bullet(b).lower() or match in b.lower()
                ):
                    new_bullets.append(line)
                    replaced = True
                else:
                    new_bullets.append(b)
            if not replaced:
                new_bullets.append(line)
            bullets = new_bullets

        try:
            path = self._write_target(target, spec.header, bullets)
        except MemoryOverflowError as exc:
            return {
                "success": False,
                "error": "overflow",
                "current_chars": exc.current_chars,
                "limit": exc.limit,
                "target": target,
                "current_entries": bullets[:20],
            }
        return {"success": True, "path": path, "action": action, "target": target}

    def read_for_prompt(self) -> str:
        blocks: list[str] = []
        disk_total = self.total_disk_chars()
        for _key, spec in MEMORY_TARGETS.items():
            if not self.notes.store.exists(spec.path):
                continue
            body = self.notes.get(spec.path).body.strip()
            if body:
                blocks.append(body)
        if not blocks:
            return ""
        combined = "\n\n".join(blocks)
        truncated = False
        if len(combined) > self.prompt_max_chars:
            truncated = True
            combined = combined[-self.prompt_max_chars :]
            combined = combined[combined.find("\n- ") :] if "\n- " in combined else combined
            combined = (
                "(Memory truncated for context; full content on disk.)\n\n" + combined.lstrip()
            )
        hint = (
            f"\n\n[Memory usage: {disk_total} / {self.disk_max_chars} chars on disk; "
            f"{min(len(combined), self.prompt_max_chars)} / {self.prompt_max_chars} in prompt]"
        )
        if truncated:
            return combined + hint
        return combined + hint

    def read(self) -> str:
        """Backward-compatible alias for :meth:`read_for_prompt`."""
        return self.read_for_prompt()

    def upsert(self, new_bullets: list[str], links: list[str] | None = None) -> str:
        """Legacy: merge bullets into ``memory`` target only."""
        bullets = self._read_bullets("memory")
        seen = set(bullets)
        for raw in new_bullets:
            line = raw if raw.strip().startswith("- ") else self._bullet_line(raw)
            if line not in seen:
                bullets.append(line)
                seen.add(line)
        spec = MEMORY_TARGETS["memory"]
        path = self._write_target("memory", spec.header, bullets)
        if links and self.notes.store.exists(path):
            concept = self.notes.get(path)
            concept.vesnai["links"] = list(
                dict.fromkeys([*concept.vesnai.get("links", []), *links])
            )
            self.notes.store.write_concept(path, concept, message="update memory links")
        return path


class MemoryOverflowError(Exception):
    def __init__(self, *, current_chars: int, limit: int, target: str) -> None:
        self.current_chars = current_chars
        self.limit = limit
        self.target = target
        super().__init__(f"memory overflow: {current_chars} > {limit}")


class MemoryConsolidator(DurableMemoryStore):
    """Legacy name + AI-assisted consolidation for manual review endpoints."""

    def __init__(self, notes: NoteService, ai: AIProvider, **kwargs: Any) -> None:
        super().__init__(notes, **kwargs)
        self.ai = ai

    def consolidate(self, recent_paths: list[str]) -> str:
        new_bullets: list[str] = []
        links: list[str] = []
        for path in recent_paths:
            c = self.notes.get(path)
            fact = self.ai.complete(f"State the single durable fact in: {c.title}. {c.body}")
            new_bullets.append(f"- {fact} ([{c.title}]({_rel(path)}))")
            links.append(path)
        return self.upsert(new_bullets, links)

    def consolidate_message(self, text: str) -> str | None:
        snippet = text.strip()
        if not snippet:
            return None
        fact = self.ai.complete(
            f"State the single durable fact worth remembering from: {snippet}"
        )
        fact = fact.strip()
        if not fact:
            return None
        return self.upsert([f"- {fact}"])


def list_playbooks_for_prompt(notes: NoteService, limit: int = 20) -> str:
    rows: list[tuple[str, str, str]] = []
    for path, concept in notes.list().items():
        if concept.type == "Playbook":
            created = str(concept.vesnai.get("created", ""))
            rows.append((created, path, concept.title or path))
    rows.sort(reverse=True)
    return "\n".join(f"- {title} ({path})" for _, path, title in rows[:limit])


class SkillService:
    """Skills are reusable procedures stored as OKF ``Playbook`` concepts."""

    def __init__(self, notes: NoteService) -> None:
        self.notes = notes

    def create_skill(self, name: str, steps: list[str]) -> str:
        body = "## Steps\n\n" + "\n".join(f"{i}. {s}" for i, s in enumerate(steps, 1))
        rel, _ = self.notes.create(
            NoteInput(title=name, body=body, type="Playbook",
                      tags=["skill"], origin=Origin.GENERATED)
        )
        return rel

    def refine_skill(self, rel_path: str, extra_step: str) -> None:
        concept = self.notes.get(rel_path)
        revision = int(concept.vesnai.get("skill_revision", 1)) + 1
        concept.vesnai["skill_revision"] = revision
        concept.body = concept.body.rstrip() + f"\n{revision}. {extra_step}"
        self.notes.store.write_concept(rel_path, concept, message=f"refine skill r{revision}")


class UserModelService:
    """An evolving user-profile concept, updated deterministically from signals."""

    PATH = "profile/user-model.md"

    def __init__(self, notes: NoteService) -> None:
        self.notes = notes

    def update(self, observations: dict[str, str]) -> str:
        if self.notes.store.exists(self.PATH):
            concept = self.notes.get(self.PATH)
            attrs = concept.vesnai.setdefault("attributes", {})
        else:
            from vesnai.okf.model import Concept

            concept = Concept(
                frontmatter={
                    "type": "UserModel",
                    "title": "User model",
                    "tags": ["generated", "profile"],
                    "vesnai": {"origin": Origin.GENERATED.value, "attributes": {}},
                },
                body="",
            )
            attrs = concept.vesnai["attributes"]
        attrs.update(observations)
        concept.body = "Known preferences:\n\n" + "\n".join(
            f"- **{k}**: {v}" for k, v in sorted(attrs.items())
        )
        self.notes.store.write_concept(self.PATH, concept, message="update user model")
        return self.PATH


class TrajectoryLog:
    def __init__(self, data_dir: Path) -> None:
        self._path = Path(data_dir) / "trajectories.jsonl"
        self._path.parent.mkdir(parents=True, exist_ok=True)

    def append(self, trajectory: dict) -> None:
        with self._path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(trajectory) + "\n")

    def all(self) -> list[dict]:
        if not self._path.exists():
            return []
        return [json.loads(line) for line in self._path.read_text().splitlines() if line.strip()]

    def compress(self) -> list[dict]:
        """Deduplicate identical trajectories, keeping first occurrence order."""
        seen: set[str] = set()
        out: list[dict] = []
        for traj in self.all():
            key = json.dumps(traj, sort_keys=True)
            if key not in seen:
                seen.add(key)
                out.append(traj)
        return out


def _rel(path: str) -> str:
    return f"../{path}"
