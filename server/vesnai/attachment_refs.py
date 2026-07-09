"""Attachment path normalization and reference scanning (no NoteService import)."""

from __future__ import annotations

import re

from vesnai.okf.model import Concept

_ATTACHMENT_BODY_RE = re.compile(r"attachments/[^)\s]+")
ENRICHMENT_CHILD_TYPES = ("GeneratedImage", "GeneratedCaption")


def normalize_bundle_path(path: str) -> str:
    return path.replace("\\", "/").strip().lstrip("./")


def attachment_paths_match(a: str, b: str) -> bool:
    left = normalize_bundle_path(a)
    right = normalize_bundle_path(b)
    return left == right or left.rsplit("/", 1)[-1] == right.rsplit("/", 1)[-1]


def attachment_refs_from_concept(concept: Concept) -> set[str]:
    refs: set[str] = set()
    for att in concept.vesnai.get("attachments") or []:
        refs.add(normalize_bundle_path(str(att)))
    for match in _ATTACHMENT_BODY_RE.finditer(concept.body or ""):
        refs.add(normalize_bundle_path(match.group(0)))
    return refs
