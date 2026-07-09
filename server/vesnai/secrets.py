"""Encrypted-at-rest secret store for external API keys.

Secrets (e.g. OpenAI/Anthropic keys) are encrypted with a Fernet key kept in the
data directory with 0600 permissions. Secret *values* are never logged and never
included in backups/exports. On devices the equivalent role is played by the OS
keychain; the server uses this encrypted file store.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from cryptography.fernet import Fernet


class SecretStore:
    def __init__(self, data_dir: Path) -> None:
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self._key_path = self.data_dir / "secret.key"
        self._store_path = self.data_dir / "secrets.enc"
        self._fernet = Fernet(self._load_or_create_key())

    def _load_or_create_key(self) -> bytes:
        if self._key_path.exists():
            return self._key_path.read_bytes()
        key = Fernet.generate_key()
        self._key_path.write_bytes(key)
        os.chmod(self._key_path, 0o600)
        return key

    def _read_all(self) -> dict[str, str]:
        if not self._store_path.exists():
            return {}
        raw = self._fernet.decrypt(self._store_path.read_bytes())
        return json.loads(raw.decode())

    def _write_all(self, data: dict[str, str]) -> None:
        token = self._fernet.encrypt(json.dumps(data).encode())
        self._store_path.write_bytes(token)
        os.chmod(self._store_path, 0o600)

    def set(self, name: str, value: str) -> None:
        data = self._read_all()
        data[name] = value
        self._write_all(data)

    def get(self, name: str) -> str | None:
        return self._read_all().get(name)

    def delete(self, name: str) -> None:
        data = self._read_all()
        data.pop(name, None)
        self._write_all(data)

    def names(self) -> list[str]:
        """Return only the *names* of stored secrets - never the values."""
        return sorted(self._read_all().keys())
