"""Parse and serialize OKF concept documents.

A concept document is::

    ---
    <yaml frontmatter>
    ---
    <markdown body>

Serialization is deterministic and round-trip stable at the structural level:
``parse(dump(c)) == (c.frontmatter, c.body)`` for any concept produced by the
parser. Well-known keys are emitted first in OKF-recommended order for
readability; remaining keys keep their insertion order.
"""

from __future__ import annotations

import yaml

from vesnai.okf.model import RECOMMENDED_ORDER, Concept

_DELIM = "---"


class OKFParseError(ValueError):
    """Raised when a concept document cannot be parsed."""


def parse_concept(text: str) -> Concept:
    """Parse a concept document into a :class:`Concept`.

    Tolerant of a leading BOM and of CRLF line endings. The body is everything
    after the closing frontmatter delimiter, with a single leading newline
    stripped (so it survives a round-trip).
    """
    if text.startswith("\ufeff"):
        text = text[1:]
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")

    if not normalized.startswith(_DELIM + "\n") and normalized.strip() != _DELIM:
        raise OKFParseError("document does not start with a '---' frontmatter delimiter")

    # Find the closing delimiter on its own line.
    lines = normalized.split("\n")
    # lines[0] == '---'
    closing_index: int | None = None
    for i in range(1, len(lines)):
        if lines[i] == _DELIM:
            closing_index = i
            break
    if closing_index is None:
        raise OKFParseError("frontmatter block is not closed with a '---' line")

    fm_text = "\n".join(lines[1:closing_index])
    body = "\n".join(lines[closing_index + 1 :])
    # A single newline immediately follows the closing delimiter in dump(); strip it.
    if body.startswith("\n"):
        body = body[1:]

    try:
        loaded = yaml.safe_load(fm_text) if fm_text.strip() else {}
    except yaml.YAMLError as exc:  # pragma: no cover - exercised via tests
        raise OKFParseError(f"invalid YAML frontmatter: {exc}") from exc

    if loaded is None:
        loaded = {}
    if not isinstance(loaded, dict):
        raise OKFParseError("frontmatter must be a YAML mapping")

    return Concept(frontmatter=dict(loaded), body=body)


def _ordered_frontmatter(frontmatter: dict) -> dict:
    ordered: dict = {}
    for key in RECOMMENDED_ORDER:
        if key in frontmatter:
            ordered[key] = frontmatter[key]
    for key, value in frontmatter.items():
        if key not in ordered:
            ordered[key] = value
    return ordered


def dump_concept(concept: Concept) -> str:
    """Serialize a :class:`Concept` to its document form (deterministic)."""
    ordered = _ordered_frontmatter(concept.frontmatter)
    fm_text = yaml.safe_dump(
        ordered,
        sort_keys=False,
        allow_unicode=True,
        default_flow_style=False,
    ).rstrip("\n")
    body = concept.body
    return f"{_DELIM}\n{fm_text}\n{_DELIM}\n{body}"
