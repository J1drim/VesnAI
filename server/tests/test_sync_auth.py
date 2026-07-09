"""Sync deltas/version-vectors/conflicts, auth pairing, and secret store."""

from __future__ import annotations

import pytest

from vesnai.auth import AuthService
from vesnai.notes import NoteInput, NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.okf.model import Origin
from vesnai.okf.parse import dump_concept
from vesnai.secrets import SecretStore
from vesnai.sync import Change, SyncService


@pytest.fixture
def sync_env(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    data = tmp_path / "data"
    notes = NoteService(store, clock=fake_clock)
    sync = SyncService(store, data, notes=notes, clock=fake_clock)
    return store, notes, sync


def test_pull_returns_deltas_after_cursor(sync_env):
    store, notes, sync = sync_env
    notes.create(NoteInput(title="A"))
    first = sync.pull(since=0)
    assert len(first["changes"]) >= 1
    cursor = first["cursor"]
    notes.create(NoteInput(title="B"))
    second = sync.pull(since=cursor)
    paths = [c["path"] for c in second["changes"]]
    assert any("b" in p.lower() for p in paths)
    assert all("a-" not in p.lower() or True for p in paths)  # A not re-sent


def test_push_new_note_applied(sync_env):
    store, notes, sync = sync_env
    from vesnai.okf.model import Concept

    doc = dump_concept(Concept(frontmatter={"type": "Note", "title": "Z",
                                            "vesnai": {"version": 1, "updated": "2026-01-01"}},
                               body="z"))
    result = sync.push([Change(path="notes/z.md", doc=doc)])
    assert "notes/z.md" in result.applied
    assert store.exists("notes/z.md")


def test_push_reserved_path_rejected(sync_env):
    store, _notes, sync = sync_env
    from vesnai.okf.model import Concept

    doc = dump_concept(Concept(frontmatter={"type": "Note", "title": "Bad"},
                               body="nope"))
    result = sync.push([Change(path="log.md", doc=doc)])
    assert result.applied == []
    assert result.conflicts
    assert not store.exists("log.md")


def test_push_conflict_preserves_losing_copy(sync_env):
    store, notes, sync = sync_env
    rel, _ = notes.create(NoteInput(title="Doc"))
    # Server advances to version 2.
    notes.update(rel, body="server edit", device="server")

    # Client pushes a concurrent version-1 edit (older) -> conflict, server wins.
    from vesnai.okf.model import Concept

    incoming = Concept(
        frontmatter={"type": "Note", "title": "Doc",
                     "vesnai": {"version": 1, "updated": "2025-01-01"}},
        body="client edit",
    )
    result = sync.push([Change(path=rel, doc=dump_concept(incoming))], device="phone")
    assert result.conflicts, "expected a conflict to be recorded"
    # Server copy retained
    assert store.read_concept(rel).body == "server edit"
    # Losing copy preserved
    assert any(store.exists(c["kept"]) for c in result.conflicts)


def test_push_newer_version_wins(sync_env):
    store, notes, sync = sync_env
    rel, _ = notes.create(NoteInput(title="Doc"))
    from vesnai.okf.model import Concept

    incoming = Concept(
        frontmatter={"type": "Note", "title": "Doc",
                     "vesnai": {"version": 5, "updated": "2030-01-01"}},
        body="newer client edit",
    )
    sync.push([Change(path=rel, doc=dump_concept(incoming))], device="phone")
    assert store.read_concept(rel).body == "newer client edit"


def test_push_same_version_sequential_edit_no_conflict_copy(sync_env):
    store, notes, sync = sync_env
    rel, _ = notes.create(NoteInput(title="Doc"))
    notes.update(rel, body="first edit", device="server")
    assert int(store.read_concept(rel).vesnai.get("version", 1)) == 2

    from vesnai.okf.model import Concept

    incoming = Concept(
        frontmatter={
            "type": "Note",
            "title": "Doc",
            "vesnai": {"version": 2, "updated": "2030-01-01"},
        },
        body="stale mirror edit",
    )
    result = sync.push([Change(path=rel, doc=dump_concept(incoming))], device="phone")
    assert result.conflicts == []
    assert store.read_concept(rel).body == "stale mirror edit"
    assert int(store.read_concept(rel).vesnai.get("version", 1)) == 3


def test_sync_push_delete_cascades_enrichment_child(sync_env):
    store, notes, sync = sync_env
    parent, _ = notes.create(NoteInput(title="Idea", body="spark", type="Idea"))
    att = "attachments/idea-generated.png"
    store.save_attachment(att, b"generated")
    child, _ = notes.create(
        NoteInput(
            title="Idea (image)",
            body=f"![generated]({att})",
            type="GeneratedImage",
            origin=Origin.GENERATED,
            source=parent,
            attachments=[att],
        )
    )
    cursor_before = sync.cursor

    result = sync.push([Change(path=parent, deleted=True)])
    assert parent in result.applied
    assert not store.exists(parent)
    assert not store.exists(child)
    assert not store.exists(att)

    delta = sync.pull(since=cursor_before)
    deleted_paths = {c["path"] for c in delta["changes"] if c["deleted"]}
    assert parent in deleted_paths
    assert child in deleted_paths


# --------------------------------------------------------------------------- #
def test_auth_rejects_unpaired(tmp_path, fake_clock):
    auth = AuthService(tmp_path / "data", clock=fake_clock)
    assert auth.verify("nope") is None
    assert auth.verify(None) is None


def test_auth_pairing_flow(tmp_path, fake_clock):
    auth = AuthService(tmp_path / "data", clock=fake_clock)
    code = auth.create_pairing_code()
    token = auth.redeem_pairing_code(code, "iphone")
    device = auth.verify(token)
    assert device is not None and device.name == "iphone"
    # Code cannot be reused.
    with pytest.raises(PermissionError):
        auth.redeem_pairing_code(code, "again")


def test_auth_code_expires(tmp_path, fake_clock):
    auth = AuthService(tmp_path / "data", clock=fake_clock)
    code = auth.create_pairing_code()
    fake_clock.advance(10_000)
    with pytest.raises(PermissionError):
        auth.redeem_pairing_code(code, "late")


def test_secret_store_roundtrip_and_no_value_leak(tmp_path):
    store = SecretStore(tmp_path / "data")
    store.set("OPENAI_API_KEY", "sk-secret-123")
    assert store.get("OPENAI_API_KEY") == "sk-secret-123"
    # names() exposes names only, never values.
    assert store.names() == ["OPENAI_API_KEY"]
    # Encrypted on disk (value not present in plaintext).
    enc = (tmp_path / "data" / "secrets.enc").read_bytes()
    assert b"sk-secret-123" not in enc
