"""Persist external TTS registration (provider + options; API key in SecretStore)."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_SECRET_NAME = "tts"
PROVIDER_SIDECAR = "sidecar"
PROVIDER_OPENAI = "openai"
OPENAI_DEFAULT_URL = "https://api.openai.com/v1"
OPENAI_DEFAULT_MODEL = "tts-1"


@dataclass
class VoiceRegistration:
    provider: str = PROVIDER_SIDECAR
    url: str = ""
    secret_name: str = DEFAULT_SECRET_NAME
    voices: dict[str, str] = field(default_factory=dict)
    model: str | None = None  # OpenAI: tts-1, gpt-4o-mini-tts, …

    def resolved_url(self) -> str:
        if self.url:
            return self.url.rstrip("/")
        if self.provider == PROVIDER_OPENAI:
            return OPENAI_DEFAULT_URL
        return ""

    def audio_content_type(self) -> str:
        if self.provider == PROVIDER_OPENAI:
            return "audio/mpeg"
        return "audio/wav"


class VoiceRegistrationStore:
    def __init__(self, data_dir: Path) -> None:
        self._path = Path(data_dir) / "voice.json"

    def load(self) -> VoiceRegistration | None:
        if not self._path.exists():
            return None
        raw = json.loads(self._path.read_text())
        provider = raw.get("provider", PROVIDER_SIDECAR)
        return VoiceRegistration(
            provider=provider,
            url=raw.get("url", ""),
            secret_name=raw.get("secret_name", DEFAULT_SECRET_NAME),
            voices=dict(raw.get("voices") or {}),
            model=raw.get("model"),
        )

    def save(self, registration: VoiceRegistration) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "provider": registration.provider,
            "url": registration.resolved_url(),
            "secret_name": registration.secret_name,
            "voices": registration.voices,
        }
        if registration.model:
            payload["model"] = registration.model
        self._path.write_text(json.dumps(payload, indent=2) + "\n")

    def delete(self) -> None:
        if self._path.exists():
            self._path.unlink()

    def is_configured(self) -> bool:
        return self._path.exists()
