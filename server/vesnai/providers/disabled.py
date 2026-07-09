"""Providers for components turned off in vesnai.yaml (mode: none).

They satisfy the provider protocols but raise a clear, user-actionable error
when used, so the rest of the stack needs no component-specific None checks.
"""

from __future__ import annotations

from vesnai.providers.base import GeneratedImage, SearchResult


class ComponentDisabledError(RuntimeError):
    """Raised when a feature disabled in the config is invoked."""


class DisabledImageProvider:
    def generate(self, prompt: str, *, seed: int | None = None) -> GeneratedImage:
        raise ComponentDisabledError(
            "Image generation is disabled (image.mode: none in vesnai.yaml)."
        )


class DisabledSTTProvider:
    def transcribe(self, audio: bytes, *, language: str | None = None) -> str:
        raise ComponentDisabledError(
            "Server-side speech-to-text is disabled (stt.mode: none in vesnai.yaml). "
            "On-device dictation in the app still works."
        )


class DisabledSearchProvider:
    def search(
        self, query: str, *, language: str = "en", max_results: int = 10
    ) -> list[SearchResult]:
        raise ComponentDisabledError(
            "Web search is disabled (search.mode: none in vesnai.yaml)."
        )

    def fetch(self, url: str) -> str:
        raise ComponentDisabledError(
            "Web search is disabled (search.mode: none in vesnai.yaml)."
        )
