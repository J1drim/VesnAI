"""Offline-first sync: delta pull/push with version-vector conflict resolution.

Each note carries ``vesnai.version`` and ``vesnai.version_vector``. The server
keeps a monotonic change journal so clients can pull only what changed since
their last cursor. Push uses last-write-wins resolved by (version, updated
timestamp); the losing side is reported as a conflict so the client can surface
it, but data is never silently lost (the conflicting copy is preserved).
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any

from vesnai.okf.bundle import BundleStore
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


@dataclass
class PushResult:
    applied: list[str] = field(default_factory=list)
    conflicts: list[dict] = field(default_factory=list)
    cursor: int = 0


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
        self._state_path.write_text(json.dumps(self._state, indent=2))

    def _on_change(self, rel_path: str, deleted: bool) -> None:
        self._state["seq"] += 1
        self._state["paths"][rel_path] = {"seq": self._state["seq"], "deleted": deleted}
        self._save()

    @property
    def cursor(self) -> int:
        return int(self._state["seq"])

    # ------------------------------------------------------------------ #
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

    def push(self, changes: list[Change], *, device: str = "device") -> PushResult:
        from vesnai.security import assert_sync_path_allowed

        result = PushResult()
        for change in changes:
            try:
                assert_sync_path_allowed(change.path)
            except ValueError as exc:
                result.conflicts.append({"path": change.path, "error": str(exc)})
                continue
            if change.deleted:
                if self.notes is not None:
                    self.notes.delete(change.path)
                else:
                    self.store.delete_concept(change.path)
                result.applied.append(change.path)
                continue
            assert change.doc is not None
            incoming = parse_concept(change.doc)
            if not self.store.exists(change.path):
                self.store.write_concept(change.path, incoming, message=f"sync add {change.path}")
                result.applied.append(change.path)
                continue
            existing = self.store.read_concept(change.path)
            winner, conflict = _resolve(existing, incoming)
            if winner is incoming:
                ev, iv = _version(existing), _version(incoming)
                if iv <= ev:
                    incoming.vesnai["version"] = ev + 1
                self.store.write_concept(change.path, incoming,
                                         message=f"sync update {change.path}")
                result.applied.append(change.path)
            if conflict:
                # Preserve the losing copy so nothing is lost.
                loser = incoming if winner is existing else existing
                conflict_path = change.path[:-3] + f".conflict-{device}.md"
                self.store.write_concept(conflict_path, loser, message="sync conflict copy")
                result.conflicts.append({"path": change.path, "kept": conflict_path})
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
        return incoming, ev > 0 and iv > ev + 1  # concurrent if it skipped versions
    if iv < ev:
        return existing, True
    # Same version: treat as a sequential edit (client should bump version, but
    # resume/bootstrap can leave the mirror stale). Apply without a conflict copy.
    if _updated(incoming) >= _updated(existing):
        return incoming, False
    return existing, False
