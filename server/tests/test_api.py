"""End-to-end API tests using the ASGI test client with fake providers."""

from __future__ import annotations

import time
from unittest.mock import patch

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
        auto_illustrate=False,  # opt-in per test to keep note counts deterministic
    )
    state = AppState(settings, clock=FakeClock())
    app = create_app(state)
    with TestClient(app) as c:
        c.state = state
        yield c


def _pair(client) -> dict:
    code = client.state.auth.create_pairing_code()
    resp = client.post("/v1/auth/pair", json={"code": code, "device_name": "test"})
    assert resp.status_code == 200
    token = resp.json()["token"]
    return {"Authorization": f"Bearer {token}"}


def test_healthz_open(client):
    assert client.get("/healthz").json()["status"] == "ok"


def test_create_session_does_not_consolidate_prior_session(client):
    """New chat must return immediately; memory updates happen per turn, not here."""
    headers = _pair(client)
    first = client.post("/v1/chat/sessions", json={}, headers=headers)
    assert first.status_code == 200
    session_id = first.json()["id"]

    accepted = client.post(
        "/v1/chat",
        json={"message": "first message in session", "session_id": session_id},
        headers=headers,
    )
    assert accepted.status_code == 202
    _wait_for_assistant_reply(client, session_id, headers)

    with patch.object(
        client.state.memory,
        "consolidate_message",
        wraps=client.state.memory.consolidate_message,
    ) as consolidate:
        start = time.monotonic()
        second = client.post("/v1/chat/sessions", json={}, headers=headers)
        elapsed = time.monotonic() - start

    assert second.status_code == 200
    assert second.json()["id"] != session_id
    assert elapsed < 1.0
    consolidate.assert_not_called()


def _wait_for_assistant_reply(client, session_id: str, headers: dict, timeout: float = 3.0) -> dict:
    deadline = time.monotonic() + timeout
    detail = None
    while time.monotonic() < deadline:
        detail = client.get(f"/v1/chat/sessions/{session_id}", headers=headers).json()
        for m in detail.get("messages", []):
            if m.get("role") == "assistant" and m.get("content"):
                return detail
        time.sleep(0.05)
    assert detail is not None
    return detail


def test_chat_turn_does_not_auto_consolidate(client):
    headers = _pair(client)
    created = client.post("/v1/chat/sessions", json={}, headers=headers)
    session_id = created.json()["id"]
    with patch.object(
        client.state.memory,
        "consolidate_message",
        wraps=client.state.memory.consolidate_message,
    ) as consolidate:
        client.post(
            "/v1/chat",
            json={"message": "hello memory test", "session_id": session_id},
            headers=headers,
        )
        _wait_for_assistant_reply(client, session_id, headers)
    consolidate.assert_not_called()


def test_chat_sessions_persist_history_and_memory(client):
    headers = _pair(client)
    # Seed durable memory; the assistant should receive it each turn.
    client.state.memory.upsert(["- The user prefers concise answers."])

    created = client.post("/v1/chat/sessions", json={}, headers=headers)
    assert created.status_code == 200
    session_id = created.json()["id"]

    first = client.post(
        "/v1/chat",
        json={"message": "remember my dog is named Bo", "session_id": session_id},
        headers=headers,
    )
    assert first.status_code == 202
    assert first.json()["status"] == "accepted"
    assert first.json()["session_id"] == session_id

    detail = _wait_for_assistant_reply(client, session_id, headers)
    roles = [m["role"] for m in detail["messages"]]
    assert roles == ["user", "assistant"]
    # The session is titled from the first user message.
    assert detail["title"].lower().startswith("remember my dog")

    listed = client.get("/v1/chat/sessions", headers=headers).json()
    assert any(s["id"] == session_id for s in listed)

    deleted = client.delete(f"/v1/chat/sessions/{session_id}", headers=headers)
    assert deleted.status_code == 200
    assert client.get(f"/v1/chat/sessions/{session_id}", headers=headers).status_code == 404


def test_chat_enqueue_is_fast_and_processes_async(client):
    headers = _pair(client)
    created = client.post("/v1/chat/sessions", json={}, headers=headers)
    session_id = created.json()["id"]

    start = time.monotonic()
    resp = client.post(
        "/v1/chat",
        json={"message": "hello queue", "session_id": session_id},
        headers=headers,
    )
    elapsed = time.monotonic() - start
    assert resp.status_code == 202
    assert resp.json()["status"] == "accepted"
    assert elapsed < 2.0

    detail = _wait_for_assistant_reply(client, session_id, headers)
    assert detail["messages"][-1]["content"]


def test_chat_fifo_two_rapid_turns(client):
    headers = _pair(client)
    created = client.post("/v1/chat/sessions", json={}, headers=headers)
    session_id = created.json()["id"]

    first = client.post(
        "/v1/chat",
        json={"message": "first turn", "session_id": session_id},
        headers=headers,
    )
    second = client.post(
        "/v1/chat",
        json={"message": "second turn", "session_id": session_id},
        headers=headers,
    )
    assert first.status_code == 202
    assert second.status_code == 202
    assert first.json()["queue_position"] == 1
    assert second.json()["queue_position"] >= 1

    deadline = time.monotonic() + 10.0
    detail = None
    while time.monotonic() < deadline:
        detail = client.get(f"/v1/chat/sessions/{session_id}", headers=headers).json()
        assistants = [
            m for m in detail.get("messages", [])
            if m.get("role") == "assistant" and m.get("content")
        ]
        if len(assistants) >= 2:
            break
        time.sleep(0.05)

    user_contents = [m["content"] for m in detail["messages"] if m["role"] == "user"]
    assert user_contents == ["first turn", "second turn"]
    assert len([m for m in detail["messages"] if m["role"] == "assistant"]) == 2


def test_chat_turn_ready_notification(client):
    headers = _pair(client)
    created = client.post("/v1/chat/sessions", json={}, headers=headers)
    session_id = created.json()["id"]

    accepted = client.post(
        "/v1/chat",
        json={"message": "ping notification", "session_id": session_id},
        headers=headers,
    )
    assistant_id = accepted.json()["assistant_message_id"]
    _wait_for_assistant_reply(client, session_id, headers)

    notes = client.get("/v1/notifications", headers=headers).json()
    ready = [n for n in notes if n.get("kind") == "chat_turn_ready"]
    assert any(n.get("session_id") == session_id for n in ready)
    assert any(n.get("message_id") == assistant_id for n in ready)


def test_chat_post_preallocates_assistant_message(client):
    headers = _pair(client)
    created = client.post("/v1/chat/sessions", json={}, headers=headers)
    session_id = created.json()["id"]

    accepted = client.post(
        "/v1/chat",
        json={"message": "stub check", "session_id": session_id},
        headers=headers,
    ).json()
    assistant_id = accepted["assistant_message_id"]
    user_id = accepted["user_message_id"]

    detail = client.get(f"/v1/chat/sessions/{session_id}", headers=headers).json()
    by_id = {m["id"]: m for m in detail["messages"]}
    assert user_id in by_id
    assert assistant_id in by_id
    assert by_id[user_id]["role"] == "user"
    assert by_id[assistant_id]["role"] == "assistant"


def test_chat_unknown_session_404(client):
    headers = _pair(client)
    resp = client.post(
        "/v1/chat", json={"message": "hi", "session_id": "missing"}, headers=headers
    )
    assert resp.status_code == 404


def test_attachment_upload_records_and_serves(client):
    headers = _pair(client)
    created = client.post(
        "/v1/notes", json={"title": "Trip", "body": "memories", "tags": []},
        headers=headers,
    )
    path = created.json()["path"]

    up = client.post(
        f"/v1/notes/{path}/attachments",
        files={"file": ("pic.png", b"\x89PNGfake", "image/png")},
        headers=headers,
    )
    assert up.status_code == 200
    rel = up.json()["attachment"]
    assert rel.startswith("attachments/")
    assert rel.endswith("-pic.png")
    assert ".." not in rel

    traversal = client.post(
        f"/v1/notes/{path}/attachments",
        files={"file": ("../notes/evil.md", b"pwn", "text/plain")},
        headers=headers,
    )
    assert traversal.status_code == 200
    evil_rel = traversal.json()["attachment"]
    assert evil_rel.startswith("attachments/")
    assert not evil_rel.endswith("evil.md") or "-" in evil_rel.split("/")[-1]
    assert client.state.store.exists(path)

    # The attachment is recorded on the note frontmatter.
    concept = client.state.store.read_concept(path)
    assert rel in concept.vesnai.get("attachments", [])

    # And the bytes are served with a guessed content-type. The full
    # bundle-relative path (incl. the `attachments/` segment) is the path param.
    served = client.get(f"/v1/attachments/{rel}", headers=headers)
    assert served.status_code == 200
    assert served.content == b"\x89PNGfake"
    assert served.headers["content-type"].startswith("image/")


def test_attachment_missing_is_404(client):
    headers = _pair(client)
    assert client.get("/v1/attachments/nope.png", headers=headers).status_code == 404


def test_protected_endpoints_reject_unpaired(client):
    assert client.get("/v1/notes").status_code == 401
    assert client.get("/v1/sync/pull").status_code == 401
    assert client.get("/v1/backup").status_code == 401


def test_pair_code_endpoint_mints_redeemable_code(client):
    bootstrap = client.state.auth.bootstrap_secret()
    resp = client.post("/v1/auth/pair/code", headers={"X-VesnAI-Bootstrap": bootstrap})
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["code"]) == 8
    assert body["code"].isalnum() and body["code"] == body["code"].upper()
    assert body["expires_in"] == 300
    assert body["url"].startswith(("http://", "https://"))
    assert "<svg" in body["qr_svg"]

    redeemed = client.post(
        "/v1/auth/pair", json={"code": body["code"], "device_name": "phone"}
    )
    assert redeemed.status_code == 200
    assert redeemed.json()["token"]


def test_pair_code_requires_bootstrap_or_device_token(client):
    # No IP-based trust: even a fresh unpaired server refuses anonymous minting
    # (tunneled requests would arrive as loopback otherwise).
    assert client.post("/v1/auth/pair/code").status_code == 403
    assert (
        client.post(
            "/v1/auth/pair/code", headers={"X-VesnAI-Bootstrap": "wrong"}
        ).status_code
        == 403
    )
    # A paired device token also works.
    headers = _pair(client)
    assert client.post("/v1/auth/pair/code", headers=headers).status_code == 200


def test_pair_code_redeem_is_case_insensitive(client):
    code = client.state.auth.create_pairing_code()
    redeemed = client.post(
        "/v1/auth/pair", json={"code": code.lower(), "device_name": "phone"}
    )
    assert redeemed.status_code == 200


def test_pair_code_rate_limited(client):
    bootstrap = client.state.auth.bootstrap_secret()
    last = None
    for _ in range(7):
        last = client.post(
            "/v1/auth/pair/code", headers={"X-VesnAI-Bootstrap": bootstrap}
        )
    assert last.status_code == 429


def test_pair_redeem_rate_limited(client):
    code = client.state.auth.create_pairing_code()
    last = None
    for i in range(22):
        last = client.post(
            "/v1/auth/pair",
            json={"code": code if i == 0 else "000000", "device_name": f"d{i}"},
        )
    assert last is not None
    assert last.status_code == 429


def test_list_and_revoke_device(client):
    headers = _pair(client)
    devices = client.get("/v1/auth/devices", headers=headers).json()
    assert len(devices) == 1
    device_id = devices[0]["device_id"]

    revoked = client.delete(f"/v1/auth/devices/{device_id}", headers=headers)
    assert revoked.json()["revoked"] is True
    # Token no longer valid after revocation.
    assert client.get("/v1/notes", headers=headers).status_code == 401


def test_full_note_flow(client):
    headers = _pair(client)
    created = client.post("/v1/notes", json={"title": "Hello", "body": "world",
                                             "tags": ["misc"]}, headers=headers)
    assert created.status_code == 200
    path = created.json()["path"]

    listed = client.get("/v1/notes", headers=headers).json()
    assert any(n["path"] == path for n in listed)

    got = client.get(f"/v1/notes/{path}", headers=headers).json()
    assert got["title"] == "Hello" and got["origin"] == "user"

    updated = client.put(f"/v1/notes/{path}", json={"body": "updated"}, headers=headers)
    assert updated.json()["body"] == "updated"

    retyped = client.put(
        f"/v1/notes/{path}", json={"type": "Task", "title": "Hello task"}, headers=headers
    )
    assert retyped.status_code == 200
    assert retyped.json()["type"] == "Task"
    assert retyped.json()["title"] == "Hello task"


def test_note_done_roundtrip_via_api(client):
    headers = _pair(client)
    created = client.post(
        "/v1/notes", json={"title": "Shopping", "body": "milk"}, headers=headers
    )
    path = created.json()["path"]
    assert created.json()["done"] is False

    marked = client.put(f"/v1/notes/{path}", json={"done": True}, headers=headers)
    assert marked.status_code == 200
    assert marked.json()["done"] is True
    assert marked.json()["done_at"]

    # Done notes never show up in the due-for-review queue.
    client.state.clock.advance(30 * 86400)
    due = client.get("/v1/notes/due", headers=headers).json()
    assert all(n["path"] != path for n in due)

    reopened = client.put(f"/v1/notes/{path}", json={"done": False}, headers=headers)
    assert reopened.json()["done"] is False
    assert reopened.json()["done_at"] is None
    due = client.get("/v1/notes/due", headers=headers).json()
    assert any(n["path"] == path for n in due)


def test_sync_pull_after_create(client):
    headers = _pair(client)
    client.post("/v1/notes", json={"title": "SyncMe"}, headers=headers)
    pull = client.get("/v1/sync/pull?since=0", headers=headers).json()
    assert pull["cursor"] >= 1
    assert any("syncme" in c["path"].lower() for c in pull["changes"])


def test_backup_restore_roundtrip(client, tmp_path):
    headers = _pair(client)
    client.post("/v1/notes", json={"title": "Backup target"}, headers=headers)
    blob = client.get("/v1/backup?allow_plaintext=true", headers=headers)
    assert blob.status_code == 200 and blob.content[:2] == b"PK"

    restored = client.post(
        "/v1/backup/restore",
        files={"file": ("backup.zip", blob.content, "application/zip")},
        headers=headers,
    )
    assert restored.json()["restored"] is True


def test_plaintext_backup_requires_opt_in(client):
    headers = _pair(client)
    denied = client.get("/v1/backup", headers=headers)
    assert denied.status_code == 400


def test_encrypted_backup_restore_roundtrip(client):
    headers = _pair(client)
    client.post("/v1/notes", json={"title": "Encrypted target"}, headers=headers)
    blob = client.post(
        "/v1/backup",
        json={"passphrase": "hunter2"},
        headers=headers,
    )
    assert blob.status_code == 200
    assert blob.content[:10] == b"VESNAIENC1"

    # Restore without passphrase is rejected.
    bad = client.post(
        "/v1/backup/restore",
        files={"file": ("b.enc", blob.content, "application/octet-stream")},
        headers=headers,
    )
    assert bad.status_code == 400

    ok = client.post(
        "/v1/backup/restore",
        data={"passphrase": "hunter2"},
        files={"file": ("b.enc", blob.content, "application/octet-stream")},
        headers=headers,
    )
    assert ok.json()["restored"] is True


def test_chat_endpoint(client):
    headers = _pair(client)
    created = client.post("/v1/chat/sessions", json={}, headers=headers)
    session_id = created.json()["id"]
    resp = client.post(
        "/v1/chat",
        json={"message": "hi vesna", "persist": True, "session_id": session_id},
        headers=headers,
    )
    assert resp.status_code == 202
    body = resp.json()
    assert body["status"] == "accepted"
    detail = _wait_for_assistant_reply(client, session_id, headers)
    assert detail["messages"][-1]["content"]


def test_voice_tts_forwards_language(client):
    headers = _pair(client)
    resp = client.post(
        "/v1/voice/tts", json={"message": "cześć VesnAI", "language": "pl"}, headers=headers
    )
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "audio/wav"
    # Fake TTS encodes the language into the audio bytes for assertions.
    assert b":pl:" in resp.content

    en = client.post("/v1/voice/tts", json={"message": "hi"}, headers=headers)
    assert b":en:" in en.content


def test_enrich_and_graph(client):
    headers = _pair(client)
    resp = client.post(
        "/v1/notes",
        json={"title": "Idea note", "type": "Idea", "body": "do something great"},
        headers=headers,
    )
    rel = resp.json()["path"]
    job = client.post("/v1/enrich", json={"path": rel, "kind": "idea"}, headers=headers).json()
    assert job["status"] == "succeeded"
    graph = client.get("/v1/graph", headers=headers).json()
    assert len(graph["nodes"]) >= 2  # source + generated child


def test_job_events_stream_terminal(client):
    headers = _pair(client)
    resp = client.post(
        "/v1/notes",
        json={"title": "SSE idea", "type": "Idea", "body": "stream me"},
        headers=headers,
    )
    rel = resp.json()["path"]
    job = client.post("/v1/enrich", json={"path": rel, "kind": "idea"}, headers=headers).json()
    job_id = job["id"]

    with client.stream("GET", f"/v1/jobs/{job_id}/events", headers=headers) as stream:
        assert stream.headers["content-type"].startswith("text/event-stream")
        payloads = [line for line in stream.iter_lines() if line.startswith("data:")]
    assert payloads, "expected at least one SSE event"
    assert '"succeeded"' in payloads[-1]


def test_settings_and_secret_no_value_echo(client):
    headers = _pair(client)
    client.post("/v1/settings/secrets", json={"name": "OPENAI_API_KEY", "value": "sk-x"},
                headers=headers)
    settings = client.get("/v1/settings", headers=headers).json()
    assert "OPENAI_API_KEY" in settings["secret_names"]
    assert "sk-x" not in str(settings)
