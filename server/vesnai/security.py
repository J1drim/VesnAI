"""Shared security helpers (upload limits, path checks, rate limits)."""

from __future__ import annotations

import re
import time
from collections import defaultdict, deque
from pathlib import Path
from urllib.parse import urlparse

from fastapi import HTTPException, UploadFile

from vesnai.ids import uuid7
from vesnai.okf.model import RESERVED_FILENAMES

MAX_UPLOAD_BYTES = 50 * 1024 * 1024

_UNSAFE_FILENAME = re.compile(r"[^\w.\-]+")

_PAIR_REDEEM_RATE = 20
_PAIR_REDEEM_WINDOW = 60.0
_pair_redeem_hits: dict[str, deque[float]] = defaultdict(deque)

# Global (all-IPs) cap: behind a tunnel every request shares one client IP, so
# a per-IP limit alone cannot bound total brute-force attempts.
_PAIR_REDEEM_GLOBAL_RATE = 60
_PAIR_REDEEM_GLOBAL_WINDOW = 300.0
_pair_redeem_global_hits: deque[float] = deque()


def sanitize_attachment_stored_rel(filename: str | None) -> str:
    """Return a safe ``attachments/{uuid}-{basename}`` path inside the bundle."""
    raw = (filename or "upload.bin").strip()
    safe_name = _UNSAFE_FILENAME.sub("_", Path(raw).name) or "upload.bin"
    if safe_name in {".", ".."} or ".." in safe_name:
        safe_name = "upload.bin"
    return f"attachments/{uuid7()}-{safe_name}"


def is_sync_path_allowed(path: str) -> bool:
    """Reject sync writes to reserved bundle paths."""
    norm = path.replace("\\", "/").strip().lstrip("/")
    if not norm:
        return False
    parts = norm.split("/")
    if parts[-1] in RESERVED_FILENAMES:
        return False
    if parts[0] == "memory":
        return False
    return True


def assert_sync_path_allowed(path: str) -> None:
    if not is_sync_path_allowed(path):
        raise ValueError(f"sync path not allowed: {path!r}")


def validate_sidecar_url(url: str) -> str:
    """Validate a user-supplied TTS sidecar base URL (allows LAN/loopback hosts)."""
    cleaned = url.strip().rstrip("/")
    parsed = urlparse(cleaned)
    if parsed.scheme not in {"http", "https"}:
        raise ValueError(f"unsupported URL scheme: {parsed.scheme!r}")
    host = (parsed.hostname or "").lower()
    if not host:
        raise ValueError("URL has no hostname")
    if host in {"169.254.169.254", "metadata.google.internal"}:
        raise ValueError("URL host is blocked")
    return cleaned


async def read_upload_bounded(
    upload: UploadFile, *, max_bytes: int = MAX_UPLOAD_BYTES
) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = await upload.read(1024 * 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise HTTPException(
                status_code=413,
                detail=f"upload exceeds {max_bytes} bytes",
            )
        chunks.append(chunk)
    return b"".join(chunks)


def rate_limit_pair_redeem(client_key: str) -> None:
    now = time.monotonic()
    while (
        _pair_redeem_global_hits
        and now - _pair_redeem_global_hits[0] > _PAIR_REDEEM_GLOBAL_WINDOW
    ):
        _pair_redeem_global_hits.popleft()
    if len(_pair_redeem_global_hits) >= _PAIR_REDEEM_GLOBAL_RATE:
        raise HTTPException(status_code=429, detail="too many pairing attempts")
    hits = _pair_redeem_hits[client_key]
    while hits and now - hits[0] > _PAIR_REDEEM_WINDOW:
        hits.popleft()
    if len(hits) >= _PAIR_REDEEM_RATE:
        raise HTTPException(status_code=429, detail="too many pairing attempts")
    hits.append(now)
    _pair_redeem_global_hits.append(now)
