"""Tag feedback API tests."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from vesnai.api.server import create_app
from vesnai.app_state import AppState
from vesnai.config import Settings
from vesnai.providers.fakes import FakeClock


@pytest.fixture
def client(tmp_path):
    settings = Settings(
        knowledge_dir=tmp_path / "kb",
        data_dir=tmp_path / "data",
        advertise_mdns=False,
        offline_only=True,
        auto_illustrate=False,
    )
    state = AppState(settings, clock=FakeClock())
    app = create_app(state)
    with TestClient(app) as c:
        c.state = state
        yield c


def _pair(client) -> dict:
    code = client.state.auth.create_pairing_code()
    resp = client.post("/v1/auth/pair", json={"code": code, "device_name": "test"})
    token = resp.json()["token"]
    return {"Authorization": f"Bearer {token}"}


def test_tag_feedback_records_and_trains_classifier(client):
    headers = _pair(client)
    resp = client.post(
        "/v1/feedback/tags",
        json={"text": "great startup idea", "tags": ["idea"], "action": "accepted"},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["recorded"] is True
    for _ in range(3):
        client.post(
            "/v1/feedback/tags",
            json={"text": "buy milk groceries", "tags": ["misc"], "action": "accepted"},
            headers=headers,
        )
    assert client.state.tag_classifier.is_trained
    assert "idea" in client.state.tag_classifier.predict("another idea for an app")


def test_due_notes_endpoint(client):
    headers = _pair(client)
    from vesnai.notes import NoteInput

    client.state.notes.create(NoteInput(title="Old note", body="body"))
    client.state.clock.advance(100 * 86400)
    resp = client.get("/v1/notes/due", headers=headers)
    assert resp.status_code == 200
    assert resp.json() == []


def test_retired_resurfacing_endpoint_preserves_metadata_and_history(client):
    headers = _pair(client)
    from vesnai.notes import NoteInput

    path, concept = client.state.notes.create(NoteInput(title="Legacy note"))
    concept.vesnai.update(resurface_count=3, last_resurfaced="2025-01-01")
    client.state.store.write_concept(path, concept)
    before = client.state.store.read_concept(path).frontmatter
    cursor = client.state.sync.cursor
    response = client.post(f"/v1/notes/{path}/resurfaced", headers=headers)
    assert response.status_code == 200
    assert response.json()["resurface_count"] == 3
    assert client.state.store.read_concept(path).frontmatter == before
    assert client.state.sync.cursor == cursor
    assert client.get("/v1/notes/due").status_code == 401
