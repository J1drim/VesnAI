"""Provider protocols and shared data types."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any, Protocol, runtime_checkable


@runtime_checkable
class Clock(Protocol):
    """Abstracts the current time so schedulers/timeouts are testable."""

    def now(self) -> datetime: ...

    def monotonic(self) -> float: ...


class SystemClock:
    """Real wall-clock + monotonic clock."""

    def now(self) -> datetime:
        return datetime.now(UTC)

    def monotonic(self) -> float:
        import time

        return time.monotonic()


# --------------------------------------------------------------------------- #
# Chat / LLM
# --------------------------------------------------------------------------- #
@dataclass
class ToolSpec:
    name: str
    description: str
    parameters: dict[str, Any] = field(default_factory=dict)


@dataclass
class ToolCall:
    name: str
    arguments: dict[str, Any] = field(default_factory=dict)
    # Provider-assigned call id. OpenAI-style endpoints require the tool result
    # message to echo it back as ``tool_call_id``; Ollama ignores it.
    id: str | None = None


@dataclass
class ChatMessage:
    role: str  # "system" | "user" | "assistant" | "tool"
    content: str = ""
    tool_calls: list[ToolCall] = field(default_factory=list)
    name: str | None = None  # tool name for role == "tool"
    tool_call_id: str | None = None  # id of the ToolCall this tool result answers
    images: list[bytes] = field(default_factory=list)  # multimodal user images


@runtime_checkable
class AIProvider(Protocol):
    """A chat/completions LLM with optional tool calling.

    ``think`` requests explicit reasoning (Qwen3.6 "thinking"); leave it off for
    low-latency interactive/tool-calling turns and on for background reasoning.
    """

    def chat(
        self,
        messages: list[ChatMessage],
        tools: list[ToolSpec] | None = None,
        *,
        temperature: float = 0.2,
        think: bool = False,
    ) -> ChatMessage: ...

    def complete(self, prompt: str, *, temperature: float = 0.2, think: bool = False) -> str: ...

    def complete_structured(
        self,
        prompt: str,
        schema: dict,
        *,
        temperature: float = 0.2,
        think: bool = False,
    ) -> str: ...


@runtime_checkable
class VisionProvider(Protocol):
    """A multimodal model that captions/describes an image."""

    def caption(self, image: bytes, prompt: str) -> str: ...


@runtime_checkable
class EmbeddingProvider(Protocol):
    def embed(self, texts: list[str]) -> list[list[float]]: ...

    @property
    def dim(self) -> int: ...


# --------------------------------------------------------------------------- #
# Image / Audio
# --------------------------------------------------------------------------- #
@dataclass
class GeneratedImage:
    data: bytes
    mime_type: str = "image/png"
    prompt: str = ""


@runtime_checkable
class ImageProvider(Protocol):
    def generate(self, prompt: str, *, seed: int | None = None) -> GeneratedImage: ...


@runtime_checkable
class TTSProvider(Protocol):
    """Text-to-speech with a girl voice by default.

    ``language`` is an optional BCP-47-ish hint (``"pl"`` | ``"en"``) so engines
    that support multiple languages (e.g. Chatterbox) speak the reply in the
    same language the user used. Single-language engines may ignore it.
    """

    def synthesize(
        self, text: str, *, voice: str | None = None, language: str | None = None
    ) -> bytes: ...


@runtime_checkable
class STTProvider(Protocol):
    def transcribe(self, audio: bytes, *, language: str | None = None) -> str: ...


# --------------------------------------------------------------------------- #
# Web search
# --------------------------------------------------------------------------- #
@dataclass
class SearchResult:
    title: str
    url: str
    snippet: str
    language: str = "en"


@runtime_checkable
class SearchProvider(Protocol):
    """Meta web search (e.g. SearXNG)."""

    def search(
        self, query: str, *, language: str = "en", max_results: int = 10
    ) -> list[SearchResult]: ...

    def fetch(self, url: str) -> str:
        """Fetch readable text content for a URL."""
        ...
