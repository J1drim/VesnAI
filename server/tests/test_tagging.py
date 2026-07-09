"""Tag suggestion endpoint and helpers."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from vesnai.ai.tagging import heuristic_tags, suggest_tags
from vesnai.api.server import create_app
from vesnai.app_state import AppState
from vesnai.config import Settings
from vesnai.providers.fakes import FakeAIProvider, FakeClock


class _JsonFakeAI(FakeAIProvider):
    def complete(self, prompt: str, *, temperature: float = 0.2, think: bool = False) -> str:
        return '{"type": "Idea", "tags": ["garden", "weekend", "maki"]}'


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


def test_heuristic_tags_defaults_to_misc():
    note_type, tags = heuristic_tags("Hello", "world")
    assert note_type == "Note"
    assert tags == ["misc"]


def test_suggest_tags_parses_json():
    result = suggest_tags(_JsonFakeAI(), title="Garden", body="weekend maki plans")
    assert result["type"] == "Idea"
    assert result["tags"] == ["garden", "weekend", "maki"]


def test_suggest_tags_api(client):
    headers = _pair(client)
    client.state.providers.reasoning = _JsonFakeAI()
    resp = client.post(
        "/v1/notes/suggest-tags",
        json={"title": "Garden", "body": "weekend maki"},
        headers=headers,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["type"] == "Idea"
    assert "garden" in data["tags"]
