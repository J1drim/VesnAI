"""Tests for saving chat attachments into the OKF knowledge bundle."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from vesnai.api.server import create_app
from vesnai.app_state import AppState
from vesnai.config import Settings
from vesnai.jobs import JobStatus
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


async def _await_job(state: AppState, job_id: str):
    job = state.jobs.get(job_id)
    assert job is not None
    queued = []
    while not state.jobs._queue.empty():
        queued.append(await state.jobs._queue.get())
    for j, func in queued:
        if j.id == job_id:
            await state.jobs._run_one(j, func)
            return state.jobs.get(job_id)
    return job


def test_save_chat_attachment_to_new_note_copies_okf_bytes(client):
    headers = _pair(client)
    session = client.post("/v1/chat/sessions", json={}, headers=headers).json()
    session_id = session["id"]
    png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
    meta = client.state.conversations.save_attachment(
        session_id, "test.png", png, kind="image"
    )
    resp = client.post(
        f"/v1/chat/sessions/{session_id}/attachments/{meta['path']}/save-to-note",
        json={"title": "Saved chat image"},
        headers=headers,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["note_path"].startswith("notes/")
    okf_path = body["attachment"]
    assert okf_path.startswith("attachments/")
    assert client.state.store.exists(okf_path)
    assert client.state.store.read_attachment(okf_path) == png
    note = client.state.notes.get(body["note_path"])
    assert okf_path in note.vesnai.get("attachments", [])
    assert okf_path in note.body


@pytest.mark.asyncio
async def test_chat_image_job_always_writes_okf_attachment(client):
    headers = _pair(client)
    session = client.post("/v1/chat/sessions", json={}, headers=headers).json()
    session_id = session["id"]
    _, assistant_id = client.state.conversations.append(session_id, "assistant", "")
    job_id = client.state._submit_chat_image_job(
        "A red balloon", session_id, assistant_id, save_to_notes=False
    )
    job = await _await_job(client.state, job_id)
    assert job is not None
    assert job.status is JobStatus.SUCCEEDED
    okf_path = job.result["okf_attachment"]
    assert okf_path.startswith("attachments/")
    assert client.state.store.exists(okf_path)
    assert client.state.store.read_attachment(okf_path)


@pytest.mark.asyncio
async def test_chat_image_job_save_to_notes_uses_okf_not_chat_url(client):
    headers = _pair(client)
    session = client.post("/v1/chat/sessions", json={}, headers=headers).json()
    session_id = session["id"]
    _, assistant_id = client.state.conversations.append(session_id, "assistant", "")
    job_id = client.state._submit_chat_image_job(
        "Sunset over mountains", session_id, assistant_id, save_to_notes=True
    )
    job = await _await_job(client.state, job_id)
    assert job.status is JobStatus.SUCCEEDED
    note_path = job.result["note_path"]
    note = client.state.notes.get(note_path)
    assert "chat:" not in note.body
    assert "attachments/" in note.body
