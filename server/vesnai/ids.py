"""Stable identifiers and filename slugs."""

from __future__ import annotations

import os
import re
import time

_SLUG_STRIP = re.compile(r"[^a-z0-9]+")


def uuid7(now_ms: int | None = None) -> str:
    """Generate a time-ordered UUIDv7-style identifier.

    Layout follows RFC 9562 v7: 48-bit millisecond timestamp, version/variant
    bits, and random fill. Sorts chronologically as a string.
    """
    ms = now_ms if now_ms is not None else int(time.time() * 1000)
    ms &= (1 << 48) - 1
    rand_a = int.from_bytes(os.urandom(2), "big") & 0x0FFF
    rand_b = int.from_bytes(os.urandom(8), "big") & ((1 << 62) - 1)
    value = ms << 80
    value |= 0x7 << 76  # version 7
    value |= rand_a << 64
    value |= 0b10 << 62  # variant
    value |= rand_b
    hex_str = f"{value:032x}"
    return f"{hex_str[0:8]}-{hex_str[8:12]}-{hex_str[12:16]}-{hex_str[16:20]}-{hex_str[20:32]}"


def slugify(text: str, *, max_len: int = 60) -> str:
    slug = _SLUG_STRIP.sub("-", text.lower()).strip("-")
    if len(slug) > max_len:
        slug = slug[:max_len].rstrip("-")
    return slug or "note"
