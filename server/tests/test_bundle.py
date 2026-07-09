"""Bundle store: git versioning, path-traversal safety, backup/restore."""

from __future__ import annotations

import pytest

from vesnai.okf.bundle import BundleStore, PathTraversalError
from vesnai.okf.model import Concept


def _note(title: str) -> Concept:
    return Concept(frontmatter={"type": "Note", "title": title}, body=f"body of {title}")


def test_write_read_roundtrip(bundle: BundleStore):
    bundle.write_concept("notes/a.md", _note("A"))
    got = bundle.read_concept("notes/a.md")
    assert got.title == "A"


def test_reserved_files_generated(bundle: BundleStore):
    bundle.write_concept("notes/a.md", _note("A"))
    assert bundle.exists("index.md")
    assert bundle.exists("log.md")
    assert "notes/a.md" not in bundle.list_paths() or "index.md" not in bundle.list_paths()
    # index/log are excluded from concept listing
    assert "index.md" not in bundle.list_paths()
    assert "log.md" not in bundle.list_paths()


def test_path_traversal_blocked(bundle: BundleStore):
    with pytest.raises(PathTraversalError):
        bundle.write_concept("../escape.md", _note("X"))
    with pytest.raises(PathTraversalError):
        bundle.read_concept("../../etc/passwd")
    with pytest.raises(PathTraversalError):
        bundle.write_concept("/abs.md", _note("X"))


def test_git_history_records_commits(bundle: BundleStore):
    bundle.write_concept("notes/a.md", _note("A"))
    bundle.write_concept("notes/b.md", _note("B"))
    history = bundle.history()
    assert len(history) >= 2


def test_backup_restore_byte_identical(tmp_path, fake_clock):
    src = BundleStore(tmp_path / "src", clock=fake_clock)
    src.write_concept("notes/a.md", _note("A"))
    src.write_concept("notes/sub/b.md", _note("B"))
    src.save_attachment("attachments/x.bin", b"\x00\x01\x02hello")
    blob = src.export_zip()

    dst = BundleStore(tmp_path / "dst", clock=fake_clock)
    dst.import_zip(blob)

    # Re-export and compare member-by-member (zip metadata aside).
    import io
    import zipfile

    def members(data: bytes) -> dict[str, bytes]:
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            return {n: zf.read(n) for n in zf.namelist()}

    assert members(blob) == members(dst.export_zip())


def test_delete_concept(bundle: BundleStore):
    bundle.write_concept("notes/a.md", _note("A"))
    assert bundle.exists("notes/a.md")
    bundle.delete_concept("notes/a.md")
    assert not bundle.exists("notes/a.md")


def test_delete_attachment(bundle: BundleStore):
    bundle.save_attachment("attachments/x.png", b"png")
    assert bundle.exists("attachments/x.png")
    bundle.delete_attachment("attachments/x.png")
    assert not bundle.exists("attachments/x.png")
