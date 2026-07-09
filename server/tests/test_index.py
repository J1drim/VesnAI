"""Tests for semantic index chunking."""

from __future__ import annotations

from vesnai.ai.index import (
    EMBED_INDEX_TEXT_MAX,
    IndexService,
    chunk_text_for_embedding,
    truncate_for_embedding,
)
from vesnai.notes import NoteInput, NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.providers.fakes import FakeEmbeddingProvider


def test_truncate_for_embedding():
    short = "hello"
    assert truncate_for_embedding(short) == short
    long = "x" * (EMBED_INDEX_TEXT_MAX + 500)
    out = truncate_for_embedding(long)
    assert len(out) <= EMBED_INDEX_TEXT_MAX
    assert out.endswith("(truncated)")


def test_chunk_text_splits_long_notes():
    body = ("paragraph one.\n\n" * 50) + ("paragraph two.\n\n" * 50)
    chunks = chunk_text_for_embedding(body, max_chars=500)
    assert len(chunks) > 1
    assert all(len(c) <= 500 for c in chunks)
    assert "paragraph one" in chunks[0]
    assert "paragraph two" in chunks[-1]


def test_index_concept_creates_multiple_chunks(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FakeEmbeddingProvider())
    body = ("section " * 400 + "\n\n") * 20
    path, concept = notes.create(NoteInput(title="Long research", body=body, type="Research"))
    index.index_concept(path, concept)
    assert index.store.count() > 1
    hits = index.search("section", top_k=3)
    assert hits
    assert hits[0].id == path


def test_index_concept_skips_on_embed_failure(tmp_path, fake_clock):
    class FailLong(FakeEmbeddingProvider):
        def embed(self, texts: list[str]) -> list[list[float]]:
            if any(len(t) > 100 for t in texts):
                raise RuntimeError("context length exceeded")
            return super().embed(texts)

    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FailLong())
    path, concept = notes.create(
        NoteInput(title="Huge", body="word " * 5000, type="Research")
    )
    index.index_concept(path, concept)
    assert index.store.count() == 0

    path2, concept2 = notes.create(NoteInput(title="Tiny", body="ok"))
    index.index_concept(path2, concept2)
    assert index.store.count() == 1


def test_remove_clears_all_chunks(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FakeEmbeddingProvider())
    body = ("chunky " * 500 + "\n\n") * 30
    path, concept = notes.create(NoteInput(title="Chunky", body=body))
    index.index_concept(path, concept)
    assert index.store.count() > 1
    index.remove(path)
    assert index.store.count() == 0
