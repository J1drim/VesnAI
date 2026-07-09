"""Note service: high-level CRUD over the OKF bundle.

Translates the app's notion of a "note" into OKF concepts with a VesnAI
frontmatter profile (stable id, origin, version vector, links). The bundle store
remains the source of truth.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from vesnai import OKF_PROFILE_VERSION
from vesnai.attachment_refs import (
    attachment_paths_match,
    attachment_refs_from_concept,
    normalize_bundle_path,
)
from vesnai.ids import slugify, uuid7
from vesnai.okf.bundle import BundleStore
from vesnai.okf.model import Concept, Origin
from vesnai.providers.base import Clock, SystemClock

DEFAULT_TYPE = "Note"


@dataclass
class NoteInput:
    title: str = ""
    body: str = ""
    type: str = DEFAULT_TYPE
    tags: list[str] = field(default_factory=list)
    origin: Origin = Origin.USER
    source: str | None = None
    links: list[str] = field(default_factory=list)
    attachments: list[str] = field(default_factory=list)
    done: bool = False
    extra: dict[str, Any] = field(default_factory=dict)


class NoteService:
    def __init__(self, store: BundleStore, clock: Clock | None = None) -> None:
        self.store = store
        self.clock = clock or SystemClock()

    def _path_for(self, note_id: str, title: str) -> str:
        return f"notes/{slugify(title) if title else 'note'}-{note_id[:8]}.md"

    def create(self, data: NoteInput) -> tuple[str, Concept]:
        note_id = uuid7(int(self.clock.now().timestamp() * 1000))
        now = self.clock.now().isoformat()
        fm: dict[str, Any] = {
            "type": data.type,
            "title": data.title,
            "tags": list(data.tags),
            "timestamp": now,
            "vesnai": {
                "id": note_id,
                "profile_version": OKF_PROFILE_VERSION,
                "origin": data.origin.value,
                "created": now,
                "updated": now,
                "version": 1,
                "version_vector": {"server": 1},
                "links": list(data.links),
                "attachments": list(data.attachments),
            },
        }
        if data.source:
            fm["vesnai"]["source"] = data.source
        if data.done:
            fm["vesnai"]["done"] = True
            fm["vesnai"]["done_at"] = now
        fm.update(data.extra)
        concept = Concept(frontmatter=fm, body=data.body)
        rel = self._path_for(note_id, data.title)
        self.store.write_concept(rel, concept, message=f"create note {note_id[:8]}")
        return rel, concept

    def update(self, rel_path: str, *, title: str | None = None, body: str | None = None,
               tags: list[str] | None = None, type: str | None = None,
               done: bool | None = None,
               device: str = "server") -> Concept:
        concept = self.store.read_concept(rel_path)
        if title is not None:
            concept.frontmatter["title"] = title
        if body is not None:
            concept.body = body
        if tags is not None:
            concept.tags = tags
        if type is not None:
            concept.frontmatter["type"] = type
        if done is not None:
            concept.vesnai["done"] = bool(done)
            if done:
                concept.vesnai["done_at"] = self.clock.now().isoformat()
            else:
                concept.vesnai.pop("done_at", None)
        v = concept.vesnai
        v["updated"] = self.clock.now().isoformat()
        v["version"] = int(v.get("version", 1)) + 1
        vv = v.setdefault("version_vector", {})
        vv[device] = int(vv.get(device, 0)) + 1
        self.store.write_concept(rel_path, concept, message=f"update {rel_path}")
        return concept

    def get(self, rel_path: str) -> Concept:
        return self.store.read_concept(rel_path)

    def _enrichment_children(self, source_path: str) -> list[str]:
        source_path = normalize_bundle_path(source_path)
        out: list[str] = []
        for rel, concept in self.list().items():
            if (
                concept.is_generated
                and concept.type in ("GeneratedImage", "GeneratedCaption")
                and concept.source == source_path
            ):
                out.append(rel)
        return out

    def _is_attachment_referenced(self, att_path: str) -> bool:
        target = normalize_bundle_path(att_path)
        for concept in self.list().values():
            for ref in attachment_refs_from_concept(concept):
                if attachment_paths_match(ref, target):
                    return True
        return False

    def delete(self, rel_path: str) -> None:
        rel_path = normalize_bundle_path(rel_path)
        if not rel_path:
            return

        for child_path in self._enrichment_children(rel_path):
            self.delete(child_path)

        orphan_candidates: set[str] = set()
        if self.store.exists(rel_path):
            orphan_candidates = attachment_refs_from_concept(self.get(rel_path))

        self.store.delete_concept(rel_path)

        for att_path in orphan_candidates:
            if att_path and not self._is_attachment_referenced(att_path):
                self.store.delete_attachment(att_path)

    def list(self) -> dict[str, Concept]:
        return self.store.list_concepts()
