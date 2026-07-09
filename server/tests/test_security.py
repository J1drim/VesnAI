"""Tests for shared security helpers."""

from __future__ import annotations

import pytest
from fastapi import HTTPException

from vesnai.security import (
    assert_sync_path_allowed,
    is_sync_path_allowed,
    rate_limit_pair_redeem,
    sanitize_attachment_stored_rel,
)


def test_sanitize_attachment_stored_rel_blocks_traversal():
    rel = sanitize_attachment_stored_rel("../notes/evil.md")
    assert rel.startswith("attachments/")
    assert ".." not in rel
    assert not rel.endswith("evil.md") or "-" in rel.split("/")[-1]


def test_sync_reserved_paths_blocked():
    assert not is_sync_path_allowed("log.md")
    assert not is_sync_path_allowed("memory/user.md")
    assert is_sync_path_allowed("notes/a.md")


def test_sync_reserved_paths_raise():
    with pytest.raises(ValueError):
        assert_sync_path_allowed("index.md")


def test_pair_redeem_rate_limit():
    for _ in range(20):
        rate_limit_pair_redeem("test-client")
    with pytest.raises(HTTPException) as exc:
        rate_limit_pair_redeem("test-client")
    assert exc.value.status_code == 429
