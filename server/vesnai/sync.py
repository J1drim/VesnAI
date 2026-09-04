"""Revision-based sync with preserved conflicts and legacy-client compatibility."""

from __future__ import annotations

import json
from copy import deepcopy
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any

from vesnai.ids import uuid7
from vesnai.okf.bundle import BundleStore, bundle_locked
from vesnai.okf.model import Concept
from vesnai.okf.parse import dump_concept, parse_concept
from vesnai.providers.base import Clock, SystemClock

if TYPE_CHECKING:
    from vesnai.notes import NoteService


@dataclass
class Change:
    path: str
    deleted: bool = False
    doc: str | None = None  # serialized concept (None when deleted)
    base_version: int | None = None


@dataclass
class PushResult:
    applied: list[str] = field(default_factory=list)
    conflicts: list[dict] = field(default_factory=list)
    cursor: int = 0
    versions: dict[str, int] = field(default_factory=dict)


class SyncService:
    def __init__(
        self,
        store: BundleStore,
        data_dir: Path,
        *,
        notes: NoteService | None = None,
        clock: Clock | None = None,
    ) -> None:
        self.store = store
        self.notes = notes
        self.clock = clock or SystemClock()
        self._state_path = Path(data_dir) / "sync_state.json"
        self._state_path.parent.mkdir(parents=True, exist_ok=True)
        self._state = self._load()
        self.store.add_observer(self._on_change)

    # ------------------------------------------------------------------ #
    def _load(self) -> dict[str, Any]:
        if self._state_path.exists():
            return json.loads(self._state_path.read_text())
        return {"seq": 0, "paths": {}}

    def _save(self) -> None:
        temporary = self._state_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self._state, indent=2))
        temporary.replace(self._state_path)

    def _on_change(self, rel_path: str, deleted: bool) -> None:
        self._state["seq"] += 1
        self._state["paths"][rel_path] = {"seq": self._state["seq"], "deleted": deleted}
        self._save()

    @property
    def cursor(self) -> int:
        return int(self._state["seq"])

    # ------------------------------------------------------------------ #
    @bundle_locked
    def pull(self, since: int = 0) -> dict[str, Any]:
        changes: list[Change] = []
        for path, meta in self._state["paths"].items():
            if meta["seq"] > since:
                if meta["deleted"]:
                    changes.append(Change(path=path, deleted=True))
                elif self.store.exists(path):
                    doc = dump_concept(self.store.read_concept(path))
                    changes.append(Change(path=path, deleted=False, doc=doc))
        changes.sort(key=lambda c: self._state["paths"][c.path]["seq"])
        return {
            "cursor": self.cursor,
            "changes": [c.__dict__ for c in changes],
        }

    @bundle_locked
    def push(self, changes: list[Change], *, device: str = "device") -> PushResult:
        from vesnai.security import assert_sync_path_allowed

        result = PushResult()
        for change in changes:
            try:
                assert_sync_path_allowed(change.path)
            except ValueError as exc:
                result.conflicts.append({"path": change.path, "error": str(exc)})
                continue
            existing = self.store.read_concept(change.path) if self.store.exists(change.path) else None
            current_version = _version(existing) if existing else 0
            if change.deleted:
                if existing and change.base_version is not None and change.base_version != current_version:
                    result.conflicts.append({
                        "path": change.path, "error": "note changed before deletion",
                        "server_doc": dump_concept(existing), "server_version": current_version,
                    })
                    continue
                if self.notes is not None:
                    self.notes.delete(change.path)
                else:
                    self.store.delete_concept(change.path)
                result.applied.append(change.path)
                result.versions[change.path] = 0
                continue
            try:
                if change.doc is None:
                    raise ValueError("note document is required")
                incoming = parse_concept(change.doc)
            except (ValueError, TypeError) as exc:
                result.conflicts.append({"path": change.path, "error": str(exc)})
                continue
            if existing is None and change.base_version not in (None, 0):
                result.conflicts.append({
                    "path": change.path, "error": "note was deleted on the server",
                    "server_doc": None, "server_version": 0,
                })
                continue
            if existing is None:
                incoming.vesnai.setdefault("id", uuid7())
                incoming.vesnai.setdefault("created", self.clock.now().isoformat())
                incoming.vesnai["version"] = 1
                self.store.write_concept(change.path, incoming, message=f"sync add {change.path}")
                result.applied.append(change.path)
                result.versions[change.path] = 1
                continue
            incoming = _merge_metadata(existing, incoming)
            if _content(existing) == _content(incoming):
                # An acknowledgement may have been lost. Replaying is idempotent.
                result.applied.append(change.path)
                result.versions[change.path] = current_version
                continue
            if change.base_version is not None:
                conflict = change.base_version != current_version
                winner = existing if conflict else incoming
            else:
                winner, conflict = _resolve(existing, incoming)
            if winner is incoming:
                ev, iv = _version(existing), _version(incoming)
                if change.base_version is not None or iv <= ev:
                    incoming.vesnai["version"] = ev + 1
                self.store.write_concept(change.path, incoming,
                                         message=f"sync update {change.path}")
                result.applied.append(change.path)
                result.versions[change.path] = _version(incoming)
            if conflict:
                # Preserve the losing copy so nothing is lost.
                loser = incoming if winner is existing else existing
                loser = deepcopy(loser)
                loser.vesnai["id"] = uuid7()
                loser.vesnai["version"] = 1
                loser.vesnai["conflict_of"] = change.path
                # A unique suffix also avoids interpreting a client device name as a path.
                conflict_path = change.path[:-3] + f".conflict-{uuid7()}.md"
                self.store.write_concept(conflict_path, loser, message="sync conflict copy")
                result.conflicts.append({
                    "path": change.path, "kept": conflict_path, "error": "concurrent edit",
                    "server_doc": dump_concept(winner), "server_version": _version(winner),
                })
        result.cursor = self.cursor
        return result


def _version(c: Concept) -> int:
    return int(c.vesnai.get("version", 1))


def _updated(c: Concept) -> str:
    return str(c.vesnai.get("updated", ""))


def _resolve(existing: Concept, incoming: Concept) -> tuple[Concept, bool]:
    """Return (winner, is_conflict). Last-write-wins by version then timestamp."""
    ev, iv = _version(existing), _version(incoming)
    if iv > ev:
        return incoming, True  # Without a base, causality cannot be established.
    if iv < ev:
        return existing, True
    # Legacy clients supply no base revision. Preserve different equal-version
    # content rather than treating a concurrent edit as a sequential one.
    if _updated(incoming) >= _updated(existing):
        return incoming, _content(existing) != _content(incoming)
    return existing, _content(existing) != _content(incoming)


def _merge_metadata(existing: Concept, incoming: Concept) -> Concept:
    fm = {**deepcopy(existing.frontmatter), **deepcopy(incoming.frontmatter)}
    fm["vesnai"] = {**deepcopy(existing.vesnai), **deepcopy(incoming.vesnai)}
    for key in ("id", "created", "profile_version", "version_vector"):
        if key in existing.vesnai:
            fm["vesnai"][key] = deepcopy(existing.vesnai[key])
    if not fm["vesnai"].get("done"):
        fm["vesnai"].pop("done_at", None)
    return Concept(frontmatter=fm, body=incoming.body)


def _content(concept: Concept) -> dict:
    fm = deepcopy(concept.frontmatter)
    fm.pop("timestamp", None)
    namespace = fm.setdefault("vesnai", {})
    for key in ("version", "version_vector", "updated", "created", "id", "profile_version"):
        namespace.pop(key, None)
    return {"frontmatter": fm, "body": concept.body}
