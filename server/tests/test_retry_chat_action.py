"""Retry chat action API tests."""

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
    return {"Authorization": f"Bearer {resp.json()['token']}"}


def test_retry_generate_image_queues_job(client):
    headers = _pair(client)
    sess = client.post("/v1/chat/sessions", headers=headers, json={"title": "t"}).json()
    session_id = sess["id"]
    client.state.conversations.append(session_id, "user", "draw a cat")
    _, asst_id = client.state.conversations.append(session_id, "assistant", "Generating…")
    client.state.conversations.update_message_metadata(
        session_id,
        asst_id,
        {
            "pending_actions": [
                {"kind": "generate_image", "prompt": "draw a cat", "status": "failed"}
            ]
        },
    )
    resp = client.post(
        f"/v1/chat/sessions/{session_id}/messages/{asst_id}/retry-action",
        headers=headers,
        json={"action": "generate_image"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["job_id"]
    assert body["status"] == "queued"
    msg = client.state.conversations.get_message(session_id, asst_id)
    assert msg is not None
    assert msg.metadata["pending_actions"][0]["kind"] == "generate_image"
    assert msg.metadata["pending_actions"][0]["status"] in ("queued", "succeeded")
