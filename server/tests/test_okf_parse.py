"""OKF parse/serialize round-trip and conformance tests."""

from __future__ import annotations

from pathlib import Path

import pytest
from hypothesis import given
from hypothesis import strategies as st

from vesnai.okf import (
    Concept,
    OKFParseError,
    Severity,
    check_bundle,
    check_concept,
    dump_concept,
    parse_concept,
)


def test_parse_basic():
    text = "---\ntype: Note\ntitle: Hello\n---\nbody text\n"
    c = parse_concept(text)
    assert c.type == "Note"
    assert c.title == "Hello"
    assert c.body == "body text\n"


def test_unknown_fields_preserved():
    text = "---\ntype: Note\nweird_key: 42\n---\nx"
    c = parse_concept(text)
    assert c.frontmatter["weird_key"] == 42
    # Round-trip keeps the unknown key.
    assert parse_concept(dump_concept(c)).frontmatter["weird_key"] == 42


def test_missing_frontmatter_raises():
    with pytest.raises(OKFParseError):
        parse_concept("no frontmatter here")


def test_unclosed_frontmatter_raises():
    with pytest.raises(OKFParseError):
        parse_concept("---\ntype: Note\nbody without closing")


def test_crlf_and_bom_tolerated():
    text = "\ufeff---\r\ntype: Note\r\n---\r\nbody\r\n"
    c = parse_concept(text)
    assert c.type == "Note"
    assert "body" in c.body


# --------------------------------------------------------------------------- #
# Property-based round trip
# --------------------------------------------------------------------------- #
_scalars = st.one_of(
    st.text(
        alphabet=st.characters(blacklist_categories=("Cs", "Cc"), blacklist_characters="\x00"),
        max_size=40,
    ),
    st.integers(min_value=-1000, max_value=1000),
    st.booleans(),
)


@given(
    fm=st.fixed_dictionaries(
        {"type": st.text(min_size=1, max_size=20).filter(lambda s: s.strip() != "")},
        optional={
            "title": st.text(max_size=40),
            "tags": st.lists(st.text(min_size=1, max_size=12), max_size=5),
            "count": st.integers(min_value=0, max_value=99),
        },
    ),
    body=st.text(
        alphabet=st.characters(blacklist_categories=("Cs", "Cc"), whitelist_characters="\n "),
        max_size=200,
    ),
)
def test_round_trip_identity(fm, body):
    concept = Concept(frontmatter=dict(fm), body=body)
    once = parse_concept(dump_concept(concept))
    twice = parse_concept(dump_concept(once))
    assert once.frontmatter == twice.frontmatter
    assert once.body == twice.body


# --------------------------------------------------------------------------- #
# Conformance
# --------------------------------------------------------------------------- #
def test_conformance_missing_type_is_error():
    c = parse_concept("---\ntitle: no type\n---\nx")
    issues = check_concept("notes/foo.md", c)
    assert any(i.severity is Severity.ERROR for i in issues)


def test_reserved_files_need_no_type():
    c = parse_concept("---\n{}\n---\n# Index\n")
    assert all(i.severity is not Severity.ERROR for i in check_concept("index.md", c))
    c2 = parse_concept("---\n{}\n---\n# Log\n")
    assert all(i.severity is not Severity.ERROR for i in check_concept("log.md", c2))


def test_broken_link_is_warning_not_error():
    a = Concept(frontmatter={"type": "Note", "title": "A"}, body="[x](missing.md)")
    issues = check_bundle({"a.md": a})
    assert any("broken cross-link" in i.message for i in issues)
    assert all(i.severity is Severity.WARNING for i in issues if "broken" in i.message)


def test_valid_internal_link_no_warning():
    a = Concept(frontmatter={"type": "Note", "title": "A"}, body="[b](b.md)")
    b = Concept(frontmatter={"type": "Note", "title": "B"}, body="")
    issues = check_bundle({"a.md": a, "b.md": b})
    assert not any("broken cross-link" in i.message for i in issues)


# --------------------------------------------------------------------------- #
# Shared cross-language fixtures
# --------------------------------------------------------------------------- #
def test_fixture_valid_bundle_passes(okf_fixtures_dir: Path):
    valid_dir = okf_fixtures_dir / "valid"
    concepts = {}
    for p in valid_dir.rglob("*.md"):
        rel = p.relative_to(valid_dir).as_posix()
        concepts[rel] = parse_concept(p.read_text(encoding="utf-8"))
    issues = check_bundle(concepts)
    assert all(i.severity is not Severity.ERROR for i in issues), issues


def test_fixture_invalid_has_error(okf_fixtures_dir: Path):
    p = okf_fixtures_dir / "invalid" / "missing-type.md"
    c = parse_concept(p.read_text(encoding="utf-8"))
    issues = check_concept("invalid/missing-type.md", c)
    assert any(i.severity is Severity.ERROR for i in issues)
