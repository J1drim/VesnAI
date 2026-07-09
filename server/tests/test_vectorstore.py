"""Vector store unit tests."""

from __future__ import annotations

from unittest.mock import MagicMock

from vesnai.ai.vectorstore import InMemoryVectorStore, QdrantVectorStore


def test_in_memory_query_orders_by_cosine():
    store = InMemoryVectorStore()
    store.upsert("a", [1.0, 0.0], {"title": "A", "path": "a"})
    store.upsert("b", [0.9, 0.1], {"title": "B", "path": "b"})
    store.upsert("c", [0.0, 1.0], {"title": "C", "path": "c"})

    hits = store.query([1.0, 0.0], top_k=2)

    assert [h.id for h in hits] == ["a", "b"]
    assert hits[0].score > hits[1].score


def test_in_memory_delete_removes_all_chunks():
    store = InMemoryVectorStore()
    store.upsert("notes/a.md::0", [1.0, 0.0], {"path": "notes/a.md"})
    store.upsert("notes/a.md::1", [0.9, 0.1], {"path": "notes/a.md"})
    store.upsert("notes/b.md", [0.0, 1.0], {"path": "notes/b.md"})
    assert store.count() == 3
    store.delete("notes/a.md")
    assert store.count() == 1
    assert "notes/b.md" in store._vectors


def test_qdrant_query_uses_query_points():
    """qdrant-client >=1.18 removed QdrantClient.search; use query_points."""
    mock_point = MagicMock()
    mock_point.id = "point-uuid"
    mock_point.score = 0.91
    mock_point.payload = {"path": "notes/trip.md", "title": "Trip"}

    mock_response = MagicMock()
    mock_response.points = [mock_point]

    mock_client = MagicMock()
    mock_client.query_points.return_value = mock_response

    store = QdrantVectorStore.__new__(QdrantVectorStore)
    store.collection = "vesnai"
    store.client = mock_client

    vector = [0.1] * 1024
    hits = store.query(vector, top_k=4)

    mock_client.query_points.assert_called_once_with(
        collection_name="vesnai",
        query=vector,
        limit=4,
    )
    assert len(hits) == 1
    assert hits[0].id == "notes/trip.md"
    assert hits[0].score == 0.91
    assert hits[0].payload["title"] == "Trip"
