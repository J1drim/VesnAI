"""Embedding index over OKF concepts for semantic search + RAG."""

from __future__ import annotations

from vesnai.ai.vectorstore import InMemoryVectorStore, VectorHit, VectorStore
from vesnai.observability import get_logger
from vesnai.okf.model import Concept
from vesnai.providers.base import EmbeddingProvider

log = get_logger("vesnai.ai.index")

# bge-m3 supports ~8192 tokens; keep a conservative char budget per chunk.
EMBED_INDEX_TEXT_MAX = 6000
EMBED_CHUNK_OVERLAP = 200


def truncate_for_embedding(text: str, *, max_chars: int = EMBED_INDEX_TEXT_MAX) -> str:
    """Trim a single embed input (queries, legacy callers)."""
    cleaned = (text or "").strip()
    if len(cleaned) <= max_chars:
        return cleaned
    suffix = "\n… (truncated)"
    keep = max(0, max_chars - len(suffix))
    return cleaned[:keep].rstrip() + suffix


def chunk_text_for_embedding(
    text: str,
    *,
    max_chars: int = EMBED_INDEX_TEXT_MAX,
    overlap: int = EMBED_CHUNK_OVERLAP,
) -> list[str]:
    """Split long note text into embed-sized chunks (paragraph-aware)."""
    cleaned = (text or "").strip()
    if not cleaned:
        return []
    if len(cleaned) <= max_chars:
        return [cleaned]

    chunks: list[str] = []
    start = 0
    while start < len(cleaned):
        end = min(start + max_chars, len(cleaned))
        if end < len(cleaned):
            split = cleaned.rfind("\n\n", start, end)
            if split <= start + max_chars // 3:
                split = cleaned.rfind("\n", start, end)
            if split > start:
                end = split
        piece = cleaned[start:end].strip()
        if piece:
            chunks.append(piece)
        if end >= len(cleaned):
            break
        start = max(end - overlap, start + 1)
    return chunks or [truncate_for_embedding(cleaned, max_chars=max_chars)]


def _chunk_id(rel_path: str, index: int) -> str:
    return f"{rel_path}::{index}"


class IndexService:
    def __init__(self, embedder: EmbeddingProvider, store: VectorStore | None = None) -> None:
        self.embedder = embedder
        self.store = store or InMemoryVectorStore()

    @staticmethod
    def _text_of(concept: Concept) -> str:
        from vesnai.ai.note_tools import attachment_extract_parts

        parts = [concept.title or "", concept.description or "", concept.body]
        parts.extend(concept.tags)
        parts.extend(attachment_extract_parts(concept))
        return "\n".join(p for p in parts if p)

    def _payload(self, rel_path: str, concept: Concept, *, chunk: int) -> dict:
        return {
            "path": rel_path,
            "title": concept.title or rel_path,
            "type": concept.type,
            "origin": concept.origin.value,
            "chunk": chunk,
        }

    def index_concept(self, rel_path: str, concept: Concept) -> None:
        self.remove(rel_path)
        chunks = chunk_text_for_embedding(self._text_of(concept))
        if not chunks:
            return
        try:
            vectors = self.embedder.embed(chunks)
        except Exception as exc:  # noqa: BLE001
            log.warning("index_embed_failed", path=rel_path, error=str(exc))
            return
        if len(vectors) != len(chunks):
            log.warning(
                "index_embed_mismatch",
                path=rel_path,
                chunks=len(chunks),
                vectors=len(vectors),
            )
            return
        for i, (chunk_text, vector) in enumerate(zip(chunks, vectors, strict=True)):
            self.store.upsert(
                _chunk_id(rel_path, i),
                vector,
                {**self._payload(rel_path, concept, chunk=i), "text_preview": chunk_text[:240]},
            )
        if len(chunks) > 1:
            log.info("index_chunked", path=rel_path, chunks=len(chunks))

    def remove(self, rel_path: str) -> None:
        self.store.delete(rel_path)

    def reindex(self, concepts: dict[str, Concept]) -> int:
        self.store.clear()
        for rel, concept in concepts.items():
            self.index_concept(rel, concept)
        return self.store.count()

    def search(self, query: str, top_k: int = 5) -> list[VectorHit]:
        try:
            vector = self.embedder.embed([truncate_for_embedding(query)])[0]
        except Exception as exc:  # noqa: BLE001
            log.warning("search_embed_failed", error=str(exc))
            return []
        # Fetch extra hits so multiple chunks from one note do not crowd out others.
        raw = self.store.query(vector, top_k=max(top_k * 4, top_k))
        best: dict[str, VectorHit] = {}
        for hit in raw:
            path = str(hit.payload.get("path") or hit.id.split("::", 1)[0])
            merged = VectorHit(id=path, score=hit.score, payload={**hit.payload, "path": path})
            prev = best.get(path)
            if prev is None or merged.score > prev.score:
                best[path] = merged
        ranked = sorted(best.values(), key=lambda h: h.score, reverse=True)
        return ranked[:top_k]
