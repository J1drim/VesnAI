"""Note delete: orphan attachment cleanup and enrichment cascade."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from vesnai.notes import NoteInput, NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.okf.model import Origin


def _run_gc(knowledge_dir: Path, *, apply: bool = False) -> subprocess.CompletedProcess:
    server_dir = Path(__file__).resolve().parents[1]
    args = [
        sys.executable,
        str(server_dir / "scripts" / "gc_orphans.py"),
        "--knowledge-dir",
        str(knowledge_dir),
    ]
    if apply:
        args.append("--apply")
    return subprocess.run(args, capture_output=True, text=True, check=False)


def test_delete_note_removes_orphan_attachment(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/photo.jpg"
    store.save_attachment(att, b"jpeg-bytes")
    path, _ = notes.create(
        NoteInput(title="Photo note", body="", type="Photo", attachments=[att])
    )
    assert store.exists(att)

    notes.delete(path)

    assert not store.exists(path)
    assert not store.exists(att)


def test_delete_note_keeps_shared_attachment(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/shared.jpg"
    store.save_attachment(att, b"shared")
    path_a, _ = notes.create(
        NoteInput(title="A", body="", attachments=[att])
    )
    path_b, _ = notes.create(
        NoteInput(title="B", body="", attachments=[att])
    )

    notes.delete(path_a)

    assert not store.exists(path_a)
    assert store.exists(path_b)
    assert store.exists(att)


def test_delete_note_removes_body_referenced_attachment(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/inline.png"
    store.save_attachment(att, b"png")
    path, _ = notes.create(
        NoteInput(title="Inline", body=f"![photo]({att})")
    )

    notes.delete(path)

    assert not store.exists(path)
    assert not store.exists(att)


def test_delete_parent_cascades_enrichment_child(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
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

    notes.delete(parent)

    assert not store.exists(parent)
    assert not store.exists(child)
    assert not store.exists(att)


def test_gc_orphans_dry_run_and_apply(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    att = "attachments/orphan.jpg"
    store.save_attachment(att, b"orphan")
    parent, _ = notes.create(NoteInput(title="Parent", body=""))
    child, _ = notes.create(
        NoteInput(
            title="Stale child",
            body="",
            type="GeneratedCaption",
            origin=Origin.GENERATED,
            source=parent,
        )
    )
    # Legacy delete: concept removed but child + attachment left behind.
    store.delete_concept(parent)

    dry = _run_gc(tmp_path / "kb")
    assert dry.returncode == 0
    assert att in dry.stdout
    assert child in dry.stdout
    assert store.exists(att)

    applied = _run_gc(tmp_path / "kb", apply=True)
    assert applied.returncode == 0
    assert not store.exists(att)
    assert not store.exists(child)
