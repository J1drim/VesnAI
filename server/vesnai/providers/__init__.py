"""Pluggable provider interfaces for all non-deterministic capabilities.

Every source of non-determinism (clock, LLM, embeddings, image generation,
TTS/STT, web search) is expressed as a small Protocol here. Production wires in
real local models (Ollama, FLUX, whisper.cpp, SearXNG); tests and the
default offline mode wire in the deterministic fakes from
:mod:`vesnai.providers.fakes`.
"""

from vesnai.providers.base import (
    AIProvider,
    ChatMessage,
    Clock,
    EmbeddingProvider,
    GeneratedImage,
    ImageProvider,
    SearchProvider,
    SearchResult,
    STTProvider,
    ToolCall,
    ToolSpec,
    TTSProvider,
    VisionProvider,
)

__all__ = [
    "Clock",
    "AIProvider",
    "VisionProvider",
    "EmbeddingProvider",
    "ImageProvider",
    "TTSProvider",
    "STTProvider",
    "SearchProvider",
    "ChatMessage",
    "ToolCall",
    "ToolSpec",
    "SearchResult",
    "GeneratedImage",
]
