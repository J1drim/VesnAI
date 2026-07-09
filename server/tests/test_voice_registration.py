"""Voice registration and remote TTS provider tests."""

from __future__ import annotations

from unittest.mock import patch

import httpx
import pytest
from fastapi.testclient import TestClient

from vesnai.api.server import create_app
from vesnai.app_state import AppState, Providers, default_fake_providers
from vesnai.config import Settings
from vesnai.providers.fakes import FakeClock
from vesnai.providers.remote_tts import RemoteTTSProvider, VoiceNotConfiguredError
from vesnai.secrets import SecretStore
from vesnai.voice_registration import (
    PROVIDER_OPENAI,
    PROVIDER_SIDECAR,
    VoiceRegistration,
    VoiceRegistrationStore,
)


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


def test_voice_registration_roundtrip_sidecar(client):
    headers = _pair(client)

    empty = client.get("/v1/settings/voice", headers=headers).json()
    assert empty["configured"] is False

    with patch("vesnai.providers.remote_tts.validate_voice_registration"):
        saved = client.put(
            "/v1/settings/voice",
            json={
                "provider": "sidecar",
                "url": "http://127.0.0.1:59125",
                "api_key": "test-key",
                "voices": {"pl": "my-voice-pl", "en": "my-voice-en"},
            },
            headers=headers,
        )
    assert saved.status_code == 200
    body = saved.json()
    assert body["configured"] is True
    assert body["provider"] == "sidecar"
    assert body["url"] == "http://127.0.0.1:59125"
    assert "test-key" not in str(body)

    settings = client.get("/v1/settings", headers=headers).json()
    assert settings["voice_configured"] is True
    assert settings["voice_provider"] == "sidecar"

    deleted = client.delete("/v1/settings/voice", headers=headers)
    assert deleted.status_code == 200
    assert deleted.json()["configured"] is False


def test_voice_registration_sidecar_requires_voices(client):
    headers = _pair(client)
    with patch("vesnai.providers.remote_tts.validate_voice_registration"):
        resp = client.put(
            "/v1/settings/voice",
            json={
                "provider": "sidecar",
                "url": "http://127.0.0.1:59125",
                "api_key": "test-key",
            },
            headers=headers,
        )
    assert resp.status_code == 400
    assert "voices" in resp.json()["detail"]


def test_voice_registration_openai(client):
    headers = _pair(client)
    with patch("vesnai.providers.remote_tts.validate_voice_registration"):
        saved = client.put(
            "/v1/settings/voice",
            json={
                "provider": "openai",
                "api_key": "sk-test",
                "voices": {"pl": "nova", "en": "shimmer"},
                "model": "tts-1",
            },
            headers=headers,
        )
    assert saved.status_code == 200
    body = saved.json()
    assert body["provider"] == "openai"
    assert body["model"] == "tts-1"
    assert body["url"] == "https://api.openai.com/v1"


def test_remote_tts_provider_posts_to_sidecar(tmp_path):
    store = VoiceRegistrationStore(tmp_path)
    store.save(
        VoiceRegistration(
            provider=PROVIDER_SIDECAR,
            url="http://tts.local",
            voices={"pl": "my-voice-pl", "en": "my-voice-en"},
        )
    )
    secrets = SecretStore(tmp_path)
    secrets.set("tts", "secret-key")

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["authorization"] == "Bearer secret-key"
        import json

        body = json.loads(request.content.decode())
        assert body["text"] == "hello"
        assert request.url.path == "/v1/synthesize"
        return httpx.Response(200, content=b"RIFF")

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = RemoteTTSProvider(store, secrets, client=client)
    assert provider.synthesize("hello", language="en") == b"RIFF"


def test_remote_tts_passes_voice_override_through(tmp_path):
    # Voice IDs are engine-specific opaque strings; explicit overrides win over
    # the registered per-language defaults.
    store = VoiceRegistrationStore(tmp_path)
    store.save(
        VoiceRegistration(
            provider=PROVIDER_SIDECAR,
            url="http://tts.local",
            voices={"pl": "my-voice-pl", "en": "my-voice-en"},
        )
    )
    secrets = SecretStore(tmp_path)
    secrets.set("tts", "secret-key")

    def handler(request: httpx.Request) -> httpx.Response:
        import json

        body = json.loads(request.content.decode())
        assert body["voice"] == "custom-voice"
        return httpx.Response(200, content=b"RIFF")

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = RemoteTTSProvider(store, secrets, client=client)
    assert provider.synthesize("hello", voice="custom-voice", language="en") == b"RIFF"


def test_remote_tts_provider_posts_to_openai(tmp_path):
    store = VoiceRegistrationStore(tmp_path)
    store.save(
        VoiceRegistration(
            provider=PROVIDER_OPENAI,
            url="https://api.openai.com/v1",
            voices={"pl": "nova", "en": "shimmer"},
            model="tts-1",
        )
    )
    secrets = SecretStore(tmp_path)
    secrets.set("tts", "sk-test")

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/audio/speech"
        import json

        body = json.loads(request.content.decode())
        assert body["input"] == "hello"
        assert body["voice"] == "shimmer"
        assert body["response_format"] == "mp3"
        return httpx.Response(200, content=b"ID3")

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = RemoteTTSProvider(store, secrets, client=client)
    assert provider.synthesize("hello", language="en") == b"ID3"


def test_remote_tts_unconfigured_raises(tmp_path):
    store = VoiceRegistrationStore(tmp_path)
    secrets = SecretStore(tmp_path)
    provider = RemoteTTSProvider(store, secrets)
    with pytest.raises(VoiceNotConfiguredError):
        provider.synthesize("hi", language="en")


def test_voice_tts_503_when_online_and_unregistered(tmp_path):
    settings = Settings(
        knowledge_dir=tmp_path / "kb",
        data_dir=tmp_path / "data",
        advertise_mdns=False,
        offline_only=False,
        auto_illustrate=False,
        tts_engine="remote",
        vector_store="in_memory",
    )
    secrets = SecretStore(settings.data_dir)
    voice_store = VoiceRegistrationStore(settings.data_dir)
    fakes = default_fake_providers()
    providers = Providers(
        ai=fakes.ai,
        embedder=fakes.embedder,
        image=fakes.image,
        tts=RemoteTTSProvider(voice_store, secrets),
        search=fakes.search,
        stt=fakes.stt,
        reasoning=fakes.reasoning,
        vision=fakes.vision,
    )
    state = AppState(settings, clock=FakeClock(), providers=providers)
    app = create_app(state)
    with TestClient(app) as client:
        client.state = state
        headers = _pair(client)
        resp = client.post(
            "/v1/voice/tts",
            json={"message": "hello", "language": "en"},
            headers=headers,
        )
        assert resp.status_code == 503
