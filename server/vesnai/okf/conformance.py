"""OKF v0.1 conformance checking.

Per the spec's permissive-consumption model, only two things are hard errors:
a non-reserved file that cannot be parsed, and a non-reserved file missing a
non-empty ``type``. Everything else (broken cross-links, unknown fields, unknown
types, missing recommended fields) is surfaced as a non-fatal warning.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from vesnai.okf.model import RESERVED_FILENAMES, Concept


class Severity(str, Enum):
    ERROR = "error"
    WARNING = "warning"


@dataclass(frozen=True)
class ConformanceIssue:
    path: str
    severity: Severity
    message: str


def _basename(path: str) -> str:
    return path.replace("\\", "/").rsplit("/", 1)[-1]


def check_concept(path: str, concept: Concept) -> list[ConformanceIssue]:
    """Validate a single already-parsed concept located at ``path``."""
    issues: list[ConformanceIssue] = []
    is_reserved = _basename(path) in RESERVED_FILENAMES

    if not is_reserved:
        if not concept.type or not concept.type.strip():
            issues.append(
                ConformanceIssue(path, Severity.ERROR, "missing required non-empty 'type'")
            )
        if not concept.title:
            issues.append(
                ConformanceIssue(path, Severity.WARNING, "recommended field 'title' is absent")
            )
    return issues


def check_bundle(concepts: dict[str, Concept]) -> list[ConformanceIssue]:
    """Validate a whole bundle (mapping of relative path -> parsed concept).

    Also reports broken cross-links (links that target a path not present in the
    bundle) as warnings, never errors.
    """
    issues: list[ConformanceIssue] = []
    known = set(concepts.keys())

    for path, concept in concepts.items():
        issues.extend(check_concept(path, concept))
        for href in concept.explicit_links():
            if _is_internal_link(href) and resolve_link(path, href, explicit=True) not in known:
                issues.append(
                    ConformanceIssue(path, Severity.WARNING, f"broken cross-link to '{href}'")
                )
        for href in concept.body_links():
            if _is_internal_link(href) and resolve_link(path, href, explicit=False) not in known:
                issues.append(
                    ConformanceIssue(path, Severity.WARNING, f"broken cross-link to '{href}'")
                )
    return issues


def resolve_link(source_path: str, href: str, *, explicit: bool) -> str:
    """Resolve a link to a canonical bundle-relative path.

    Explicit (``vesnai.links``) links are already bundle-root-relative; body
    Markdown links are relative to the source file's directory.
    """
    href = href.split("#", 1)[0]
    if explicit:
        return href.lstrip("./").lstrip("/")
    return _normalize_target(source_path, href)


def _is_internal_link(href: str) -> bool:
    if "://" in href or href.startswith(("#", "mailto:")):
        return False
    return href.endswith(".md") or "/" in href or not href.startswith("http")


def _normalize_target(source_path: str, href: str) -> str:
    """Resolve a relative link from ``source_path`` to a bundle-relative path."""
    href = href.split("#", 1)[0]
    if href.startswith("/"):
        return href.lstrip("/")
    base_parts = source_path.replace("\\", "/").split("/")[:-1]
    parts = base_parts + href.split("/")
    resolved: list[str] = []
    for part in parts:
        if part in ("", "."):
            continue
        if part == "..":
            if resolved:
                resolved.pop()
            continue
        resolved.append(part)
    return "/".join(resolved)
