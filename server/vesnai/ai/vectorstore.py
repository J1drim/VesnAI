"""Vector store abstraction with an in-memory default and optional Qdrant backend.

The in-memory store is exact (cosine) and dependency-free, so semantic search and
RAG are fully testable. Qdrant (Apache-2.0) is used in production when available;
both implement the same :class:`VectorStore` protocol. The index is always
rebuildable from the OKF bundle, so it is never the source of truth.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any, Protocol, runtime_checkable


@dataclass
class VectorHit:
    id: str
    score: float
    payload: dict[str, Any] = field(default_factory=dict)


@runtime_checkable
class VectorStore(Protocol):
    def upsert(self, id: str, vector: list[float], payload: dict[str, Any]) -> None: ...

    def delete(self, id: str) -> None: ...

    def query(self, vector: list[float], top_k: int = 5) -> list[VectorHit]: ...

    def clear(self) -> None: ...

    def count(self) -> int: ...


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b, strict=False))
    na = math.sqrt(sum(x * x for x in a)) or 1.0
    nb = math.sqrt(sum(y * y for y in b)) or 1.0
    return dot / (na * nb)


class InMemoryVectorStore:
    def __init__(self) -> None:
        self._vectors: dict[str, list[float]] = {}
        self._payloads: dict[str, dict[str, Any]] = {}

    def upsert(self, id: str, vector: list[float], payload: dict[str, Any]) -> None:
        self._vectors[id] = list(vector)
        self._payloads[id] = dict(payload)

    def delete(self, id: str) -> None:
        prefix = f"{id}::"
        for key in list(self._vectors.keys()):
            if key == id or key.startswith(prefix):
                self._vectors.pop(key, None)
                self._payloads.pop(key, None)

    def query(self, vector: list[float], top_k: int = 5) -> list[VectorHit]:
        scored = [
            VectorHit(id=i, score=cosine(vector, v), payload=self._payloads.get(i, {}))
            for i, v in self._vectors.items()
        ]
        scored.sort(key=lambda h: h.score, reverse=True)
        return scored[:top_k]

    def clear(self) -> None:
        self._vectors.clear()
        self._payloads.clear()

    def count(self) -> int:
        return len(self._vectors)


class QdrantVectorStore:
    """Qdrant-backed store (optional). Requires ``qdrant-client``.

    Used in production when offline mode is disabled and Qdrant is reachable.
    Implements the same :class:`VectorStore` protocol as the in-memory store.
    """

    def __init__(self, dim: int, *, url: str = "http://127.0.0.1:6333",
                 collection: str = "vesnai") -> None:
        from qdrant_client import QdrantClient
        from qdrant_client.models import Distance, VectorParams

        self.collection = collection
        self.client = QdrantClient(url=url)
        if self.client.collection_exists(collection):
            # Changing the embedding model/provider changes vector dimensions.
            # Notes are the source of truth (the index is rebuilt on startup),
            # so recreating the collection is safe and automatic.
            existing = self._existing_dim()
            if existing is not None and existing != dim:
                from vesnai.observability import get_logger

                get_logger("vesnai.vectorstore").warning(
                    "qdrant_dim_changed_recreating",
                    collection=collection,
                    old_dim=existing,
                    new_dim=dim,
                )
                self.client.delete_collection(collection)
        if not self.client.collection_exists(collection):
            self.client.create_collection(
                collection,
                vectors_config=VectorParams(size=dim, distance=Distance.COSINE),
            )

    def _existing_dim(self) -> int | None:
        try:
            info = self.client.get_collection(self.collection)
            params = info.config.params.vectors
            size = getattr(params, "size", None)
            if size is None and isinstance(params, dict):
                first = next(iter(params.values()), None)
                size = getattr(first, "size", None)
            return int(size) if size is not None else None
        except Exception:  # noqa: BLE001 - best-effort introspection
            return None

    @staticmethod
    def _point_id(rel_path: str) -> str:
        import uuid

        return str(uuid.uuid5(uuid.NAMESPACE_URL, rel_path))

    def upsert(self, id: str, vector: list[float], payload: dict) -> None:
        from qdrant_client.models import PointStruct

        self.client.upsert(
            self.collection,
            points=[PointStruct(id=self._point_id(id), vector=vector,
                                payload={**payload, "path": payload.get("path", id.split("::", 1)[0])})],
        )

    def delete(self, id: str) -> None:
        from qdrant_client.models import FieldCondition, Filter, MatchValue

        self.client.delete(
            self.collection,
            points_selector=Filter(
                must=[FieldCondition(key="path", match=MatchValue(value=id))]
            ),
        )

    def query(self, vector: list[float], top_k: int = 5) -> list[VectorHit]:
        res = self.client.query_points(
            collection_name=self.collection,
            query=vector,
            limit=top_k,
        )
        return [
            VectorHit(
                id=str((p.payload or {}).get("path", p.id)),
                score=p.score,
                payload=dict(p.payload or {}),
            )
            for p in res.points
        ]

    def clear(self) -> None:
        from qdrant_client.models import Filter

        self.client.delete(self.collection, points_selector=Filter())

    def count(self) -> int:
        return self.client.count(self.collection).count
