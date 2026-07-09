"""FLUX prompt builders for VesnAI-generated images."""

from __future__ import annotations

_MEMORY_BODY_MAX_CHARS = 500

_MEMORY_STYLE = (
    "Style: vintage indie zine illustration, muted sage-green and sepia palette, "
    "risograph texture with subtle film grain, symbolic surreal shapes, "
    "hand-printed editorial poster aesthetic. Not photorealistic, not glossy 3D render."
)

_CHAT_STYLE_SUFFIX = (
    "If no other style is specified, render as a muted vintage editorial illustration "
    "with warm tones and subtle print texture."
)


def _trim_body(body: str, *, max_chars: int = _MEMORY_BODY_MAX_CHARS) -> str:
    text = " ".join(body.split())
    if len(text) <= max_chars:
        return text
    return text[: max_chars - 1].rstrip() + "…"


def build_memory_image_prompt(title: str, body: str) -> str:
    """Build a FLUX prompt for note memory-aid images (abstract, vintage)."""
    subject = _trim_body(body)
    return (
        f"An abstract, emotionally memorable memory symbol about: {title}. {subject}. "
        f"{_MEMORY_STYLE}"
    )


def build_chat_image_prompt(user_prompt: str) -> str:
    """Build a FLUX prompt for chat images; user text first, vintage default trailing."""
    prompt = user_prompt.strip()
    if not prompt:
        return _CHAT_STYLE_SUFFIX
    return f"{prompt}. {_CHAT_STYLE_SUFFIX}"
