"""Deterministic fake providers.

These power the test suite and the default fully-offline mode, so the entire
system runs and is verifiable without any heavyweight models. They are
deterministic: same input -> same output, no network, no randomness unless a
seed is supplied.
"""

from __future__ import annotations

import hashlib
import math
import re
from datetime import UTC, datetime, timedelta

from vesnai.providers.base import (
    ChatMessage,
    GeneratedImage,
    SearchResult,
    ToolSpec,
)

_WORD = re.compile(r"[a-zA-Z\u00c0-\u024f]+")


class FakeClock:
    """A controllable clock for deterministic time-based tests."""

    def __init__(self, start: datetime | None = None) -> None:
        self._now = start or datetime(2026, 1, 1, tzinfo=UTC)
        self._mono = 0.0

    def now(self) -> datetime:
        return self._now

    def monotonic(self) -> float:
        return self._mono

    def advance(self, seconds: float) -> None:
        self._now = self._now + timedelta(seconds=seconds)
        self._mono += seconds


class FakeAIProvider:
    """A scriptable chat model.

    If ``scripted`` responses are provided, they are returned in order (handy for
    asserting exact tool-call sequences). Otherwise it produces a deterministic,
    content-derived reply and can emit tool calls when ``auto_tool`` matches.
    """

    def __init__(self, scripted: list[ChatMessage] | None = None) -> None:
        self._scripted = list(scripted or [])
        self._i = 0

    def chat(
        self,
        messages: list[ChatMessage],
        tools: list[ToolSpec] | None = None,
        *,
        temperature: float = 0.2,
        think: bool = False,
    ) -> ChatMessage:
        if self._i < len(self._scripted):
            msg = self._scripted[self._i]
            self._i += 1
            return msg
        last = messages[-1].content if messages else ""
        return ChatMessage(role="assistant", content=f"[fake-reply] {last[:200]}")

    def complete(self, prompt: str, *, temperature: float = 0.2, think: bool = False) -> str:
        # Deterministic 1-sentence "summary": first 12 words.
        words = _WORD.findall(prompt)
        return " ".join(words[:12]) or "(empty)"

    def complete_structured(
        self,
        prompt: str,
        schema: dict,
        *,
        temperature: float = 0.2,
        think: bool = False,
    ) -> str:
        return self.complete(prompt, temperature=temperature, think=think)


class FakeVisionProvider:
    """Deterministic image captioner: derives a stable caption from the prompt."""

    def caption(self, image: bytes, prompt: str) -> str:
        words = _WORD.findall(prompt)
        digest = hashlib.sha256(image).hexdigest()[:6]
        return f"[fake-caption {digest}] {' '.join(words[:10])}".strip()


class FakeEmbeddingProvider:
    """Hash-based deterministic embeddings (bag-of-words into a fixed vector)."""

    def __init__(self, dim: int = 64) -> None:
        self._dim = dim

    @property
    def dim(self) -> int:
        return self._dim

    def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._embed_one(t) for t in texts]

    def _embed_one(self, text: str) -> list[float]:
        vec = [0.0] * self._dim
        for word in _WORD.findall(text.lower()):
            h = int(hashlib.sha256(word.encode()).hexdigest(), 16)
            vec[h % self._dim] += 1.0
        norm = math.sqrt(sum(v * v for v in vec)) or 1.0
        return [v / norm for v in vec]


class FakeImageProvider:
    """Returns a tiny deterministic PNG (1x1) whose bytes depend on the prompt."""

    def generate(self, prompt: str, *, seed: int | None = None) -> GeneratedImage:
        digest = hashlib.sha256(f"{seed}:{prompt}".encode()).digest()
        # Minimal valid 1x1 PNG with the color derived from the digest.
        png = _solid_png(digest[0], digest[1], digest[2])
        return GeneratedImage(data=png, mime_type="image/png", prompt=prompt)


class FakeTTSProvider:
    def synthesize(
        self, text: str, *, voice: str | None = None, language: str | None = None
    ) -> bytes:
        header = f"VESNAI-FAKE-WAV:{voice or 'vesna'}:{language or 'auto'}:".encode()
        return header + hashlib.sha256(text.encode()).digest()


class FakeSTTProvider:
    def __init__(self, transcript: str = "fake transcript") -> None:
        self._transcript = transcript

    def transcribe(self, audio: bytes, *, language: str | None = None) -> str:
        return self._transcript


class FakeSearchProvider:
    """Returns fixture results from an in-memory index keyed by substring."""

    def __init__(self, fixtures: dict[str, list[SearchResult]] | None = None) -> None:
        self._fixtures = fixtures or {}
        self._pages: dict[str, str] = {}

    def add(self, keyword: str, results: list[SearchResult]) -> None:
        self._fixtures[keyword.lower()] = results

    def add_page(self, url: str, content: str) -> None:
        self._pages[url] = content

    def search(
        self, query: str, *, language: str = "en", max_results: int = 10
    ) -> list[SearchResult]:
        out: list[SearchResult] = []
        q = query.lower()
        for keyword, results in self._fixtures.items():
            if keyword in q:
                out.extend(r for r in results if r.language in (language, "*"))
        if not out:
            # Deterministic synthetic result so the agent always has something.
            out = [
                SearchResult(
                    title=f"Result for {query}",
                    url=f"https://example.test/{hashlib.sha256(query.encode()).hexdigest()[:8]}",
                    snippet=f"Synthetic snippet about {query}.",
                    language=language,
                )
            ]
        return out[:max_results]

    def fetch(self, url: str) -> str:
        return self._pages.get(url, f"Readable content of {url}.")


def _solid_png(r: int, g: int, b: int) -> bytes:
    """Build a minimal valid 1x1 RGB PNG with the given color (no deps)."""
    import struct
    import zlib

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    raw = b"\x00" + bytes([r, g, b])
    idat = zlib.compress(raw)
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
