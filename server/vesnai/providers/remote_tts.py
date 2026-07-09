"""HTTP TTS clients for registered voice backends (sidecar, OpenAI, …)."""

from __future__ import annotations

from typing import Protocol

import httpx

from vesnai.voice_registration import (
    OPENAI_DEFAULT_MODEL,
    PROVIDER_OPENAI,
    PROVIDER_SIDECAR,
    VoiceRegistration,
    VoiceRegistrationStore,
)


class VoiceNotConfiguredError(RuntimeError):
    """Raised when no voice service is registered or the API key is missing."""


class SecretReader(Protocol):
    def get(self, name: str) -> str | None: ...


class UnavailableTTSProvider:
    def synthesize(
        self, text: str, *, voice: str | None = None, language: str | None = None
    ) -> bytes:
        raise VoiceNotConfiguredError(
            "No voice service registered. Add one in Settings → Voice service."
        )


class RemoteTTSProvider:
    def __init__(
        self,
        voice_store: VoiceRegistrationStore,
        secrets: SecretReader,
        *,
        client: httpx.Client | None = None,
    ) -> None:
        self.voice_store = voice_store
        self.secrets = secrets
        self._client = client

    def _registration(self) -> VoiceRegistration:
        reg = self.voice_store.load()
        if reg is None:
            raise VoiceNotConfiguredError(
                "No voice service registered. Add one in Settings → Voice service."
            )
        return reg

    def _api_key(self, secret_name: str) -> str:
        key = self.secrets.get(secret_name)
        if not key:
            raise VoiceNotConfiguredError(
                "Voice service API key is missing. Re-register in Settings → Voice service."
            )
        return key

    def synthesize(
        self, text: str, *, voice: str | None = None, language: str | None = None
    ) -> bytes:
        reg = self._registration()
        api_key = self._api_key(reg.secret_name)
        client = self._client or httpx.Client(timeout=120.0)
        own_client = self._client is None
        try:
            if reg.provider == PROVIDER_OPENAI:
                return _synthesize_openai(reg, api_key, text, voice=voice, language=language, client=client)
            return _synthesize_sidecar(reg, api_key, text, voice=voice, language=language, client=client)
        finally:
            if own_client:
                client.close()


def _pick_voice(
    reg: VoiceRegistration, *, voice: str | None, language: str | None
) -> str | None:
    # Voice IDs are engine-specific opaque strings; pass them through as-is.
    if voice:
        return voice
    lang = (language or "en").lower()
    return reg.voices.get(lang) or reg.voices.get("en")


def _synthesize_sidecar(
    reg: VoiceRegistration,
    api_key: str,
    text: str,
    *,
    voice: str | None,
    language: str | None,
    client: httpx.Client,
) -> bytes:
    base = reg.resolved_url()
    if not base:
        raise VoiceNotConfiguredError("Sidecar URL is not configured.")
    lang = (language or "en").lower()
    voice_name = _pick_voice(reg, voice=voice, language=language)
    payload: dict[str, str] = {"text": text}
    if voice_name:
        payload["voice"] = voice_name
    else:
        payload["language"] = lang

    resp = client.post(
        f"{base}/v1/synthesize",
        json=payload,
        headers={"Authorization": f"Bearer {api_key}"},
    )
    if resp.status_code == 401:
        raise VoiceNotConfiguredError("Voice service rejected the API key.")
    resp.raise_for_status()
    return resp.content


def _synthesize_openai(
    reg: VoiceRegistration,
    api_key: str,
    text: str,
    *,
    voice: str | None,
    language: str | None,
    client: httpx.Client,
) -> bytes:
    voice_name = _pick_voice(reg, voice=voice, language=language) or "nova"
    model = reg.model or OPENAI_DEFAULT_MODEL
    base = reg.resolved_url()
    resp = client.post(
        f"{base}/audio/speech",
        json={
            "model": model,
            "input": text,
            "voice": voice_name,
            "response_format": "mp3",
        },
        headers={"Authorization": f"Bearer {api_key}"},
    )
    if resp.status_code == 401:
        raise VoiceNotConfiguredError("OpenAI rejected the API key.")
    resp.raise_for_status()
    return resp.content


def validate_voice_registration(reg: VoiceRegistration, api_key: str) -> None:
    """Verify credentials with a short synthesis before saving registration."""
    from vesnai.ai.web_safety import UnsafeUrlError, validate_public_http_url
    from vesnai.security import validate_sidecar_url

    if reg.provider == PROVIDER_OPENAI:
        try:
            validate_public_http_url(reg.resolved_url())
        except UnsafeUrlError as exc:
            raise ValueError(str(exc)) from exc
        _validate_openai(reg, api_key)
    elif reg.provider == PROVIDER_SIDECAR:
        try:
            validate_sidecar_url(reg.resolved_url())
        except ValueError as exc:
            raise ValueError(str(exc)) from exc
        _validate_sidecar(reg, api_key)
    else:
        raise ValueError(f"unsupported voice provider: {reg.provider!r}")


def _validate_sidecar(reg: VoiceRegistration, api_key: str) -> None:
    base = reg.resolved_url()
    if not base:
        raise ValueError("url is required for the sidecar provider")
    headers = {"Authorization": f"Bearer {api_key}"}
    with httpx.Client(timeout=60.0) as client:
        health = client.get(f"{base}/healthz")
        health.raise_for_status()
        synth = client.post(
            f"{base}/v1/synthesize",
            json={"text": "VesnAI voice check.", "language": "en"},
            headers=headers,
        )
        if synth.status_code == 401:
            raise ValueError("invalid API key for the voice service")
        synth.raise_for_status()
        if not synth.content:
            raise ValueError("voice service returned empty audio")


def _validate_openai(reg: VoiceRegistration, api_key: str) -> None:
    with httpx.Client(timeout=60.0) as client:
        resp = client.post(
            f"{reg.resolved_url()}/audio/speech",
            json={
                "model": reg.model or OPENAI_DEFAULT_MODEL,
                "input": "VesnAI voice check.",
                "voice": reg.voices.get("en") or reg.voices.get("pl") or "nova",
                "response_format": "mp3",
            },
            headers={"Authorization": f"Bearer {api_key}"},
        )
        if resp.status_code == 401:
            raise ValueError("invalid OpenAI API key")
        resp.raise_for_status()
        if not resp.content:
            raise ValueError("OpenAI returned empty audio")
