#!/usr/bin/env python3
"""Remove orphaned bundle attachments and stale enrichment child notes.

Usage:
  python -m scripts.gc_orphans --knowledge-dir /path/to/kb          # dry-run
  python -m scripts.gc_orphans --knowledge-dir /path/to/kb --apply  # delete

Run from the ``server/`` directory (or ensure ``vesnai`` is importable).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from vesnai.ai.note_tools import (
    is_attachment_referenced,
    stale_enrichment_children,
)
from vesnai.notes import NoteService
from vesnai.okf.bundle import BundleStore


def _orphan_attachments(store: BundleStore, notes: NoteService) -> list[tuple[str, int]]:
    orphans: list[tuple[str, int]] = []
    for rel in store.list_attachment_paths():
        if is_attachment_referenced(notes, rel):
            continue
        try:
            size = len(store.read_attachment(rel))
        except OSError:
            size = 0
        orphans.append((rel, size))
    return orphans


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--knowledge-dir", type=Path, required=True)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Delete orphans (default is dry-run)",
    )
    args = parser.parse_args()

    store = BundleStore(args.knowledge_dir.resolve(), use_git=True)
    notes = NoteService(store)

    stale_children = stale_enrichment_children(notes)
    orphan_atts = _orphan_attachments(store, notes)
    bytes_total = sum(size for _, size in orphan_atts)

    print(f"Stale enrichment notes: {len(stale_children)}")
    for path in stale_children:
        print(f"  note {path}")

    print(f"Orphan attachments: {len(orphan_atts)} ({bytes_total} bytes)")
    for path, size in orphan_atts:
        print(f"  {path} ({size} bytes)")

    if not args.apply:
        print("\nDry-run only. Pass --apply to delete.")
        return 0

    for path in stale_children:
        notes.delete(path)
        print(f"deleted note {path}")

    for path, _ in orphan_atts:
        store.delete_attachment(path)
        print(f"deleted attachment {path}")

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
