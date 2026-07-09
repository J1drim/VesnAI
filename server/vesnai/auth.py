"""Device-pairing authentication.

Onboarding: the server shows a short pairing code (also encodable as a QR). A new
device redeems the code to receive a long-lived per-device bearer token. Tokens
are stored hashed (never in plaintext). Every protected endpoint requires a valid
token; unpaired devices are rejected.

Minting a pairing code over HTTP always requires either a paired device token
or the *bootstrap secret* — a random value generated into ``data_dir`` on first
start with mode 0600. IP-based trust (loopback bypass) is intentionally absent:
tunnels (pinggy/ngrok/cloudflared) forward from the same machine, so every
tunneled request would otherwise arrive as 127.0.0.1 with local privileges.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

from vesnai.providers.base import Clock, SystemClock

PAIRING_TTL_SECONDS = 300
# Unambiguous uppercase alphanumerics (no 0/O/1/I): 8 chars ≈ 40 bits.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 8
# Global cap on outstanding codes: behind a tunnel all traffic shares one IP,
# so per-IP limits alone cannot bound the number of live codes.
MAX_PENDING_CODES = 20

BOOTSTRAP_SECRET_FILENAME = "bootstrap_secret"


class TooManyPendingCodesError(RuntimeError):
    """Raised when the outstanding pairing-code cap is reached."""


@dataclass
class Device:
    device_id: str
    name: str
    created: str


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class AuthService:
    def __init__(self, data_dir: Path, clock: Clock | None = None) -> None:
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self._path = self.data_dir / "devices.json"
        self._bootstrap_path = self.data_dir / BOOTSTRAP_SECRET_FILENAME
        self.clock = clock or SystemClock()
        self._pending: dict[str, datetime] = {}  # pairing_code -> expiry

    # ------------------------------------------------------------------ #
    def _load(self) -> dict[str, dict]:
        if not self._path.exists():
            return {}
        return json.loads(self._path.read_text())

    def _save(self, data: dict[str, dict]) -> None:
        self._path.write_text(json.dumps(data, indent=2))
        try:
            os.chmod(self._path, 0o600)
        except OSError:  # pragma: no cover - exotic filesystems
            pass

    # ------------------------------------------------------------------ #
    def bootstrap_secret(self) -> str:
        """Read (or create on first use) the host-only pairing bootstrap secret."""
        if self._bootstrap_path.exists():
            return self._bootstrap_path.read_text().strip()
        secret = secrets.token_urlsafe(32)
        self._bootstrap_path.write_text(secret + "\n")
        try:
            os.chmod(self._bootstrap_path, 0o600)
        except OSError:  # pragma: no cover
            pass
        return secret

    def verify_bootstrap_secret(self, value: str | None) -> bool:
        if not value or not self._bootstrap_path.exists():
            return False
        return hmac.compare_digest(value.strip(), self.bootstrap_secret())

    # ------------------------------------------------------------------ #
    def _purge_expired(self) -> None:
        now = self.clock.now()
        for code, expiry in list(self._pending.items()):
            if now > expiry:
                del self._pending[code]

    def create_pairing_code(self) -> str:
        self._purge_expired()
        if len(self._pending) >= MAX_PENDING_CODES:
            raise TooManyPendingCodesError(
                "too many outstanding pairing codes; retry after one expires"
            )
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
        self._pending[code] = self.clock.now() + timedelta(seconds=PAIRING_TTL_SECONDS)
        return code

    def redeem_pairing_code(self, code: str, device_name: str) -> str:
        normalized = code.strip().upper()
        expiry = self._pending.get(normalized)
        if expiry is None or self.clock.now() > expiry:
            self._pending.pop(normalized, None)
            raise PermissionError("invalid or expired pairing code")
        del self._pending[normalized]

        token = secrets.token_urlsafe(32)
        device_id = secrets.token_hex(8)
        data = self._load()
        data[_hash_token(token)] = {
            "device_id": device_id,
            "name": device_name,
            "created": self.clock.now().isoformat(),
        }
        self._save(data)
        return token

    def verify(self, token: str | None) -> Device | None:
        if not token:
            return None
        hashed = _hash_token(token)
        # compare_digest over the (small) device set instead of a dict lookup,
        # so the membership check itself is timing-safe.
        record = None
        for key, rec in self._load().items():
            if hmac.compare_digest(key, hashed):
                record = rec
        if not record:
            return None
        return Device(record["device_id"], record["name"], record["created"])

    def revoke(self, device_id: str) -> None:
        data = self._load()
        for key, rec in list(data.items()):
            if rec["device_id"] == device_id:
                del data[key]
        self._save(data)

    def list_devices(self) -> list[Device]:
        return [Device(r["device_id"], r["name"], r["created"]) for r in self._load().values()]
