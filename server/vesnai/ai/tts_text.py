"""Turn an LLM chat reply into plain text suitable for speech synthesis.

Assistant replies often contain markdown (bold, lists, links, code fences) and
URLs that a TTS model reads literally ("asterisk asterisk", "h-t-t-p-s colon
slash slash ..."), which makes Polish output especially hard to follow. This
module strips that formatting down to the words a person would actually say.
"""

from __future__ import annotations

import re

_FENCED_CODE = re.compile(r"```.*?```", re.DOTALL)
_INLINE_CODE = re.compile(r"`([^`]*)`")
_MD_LINK = re.compile(r"\[([^\]]+)\]\([^)]*\)")
_BARE_URL = re.compile(r"https?://\S+")
_EMPHASIS = re.compile(r"(\*{1,3}|_{1,3}|~~)")
_LIST_MARKER = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+", re.MULTILINE)
_HEADING = re.compile(r"^\s*#{1,6}\s*", re.MULTILINE)
_BLOCKQUOTE = re.compile(r"^\s*>\s?", re.MULTILINE)
_EMOJI = re.compile(
    "[" "\U0001f000-\U0001faff" "\U00002600-\U000027bf" "\U0001f1e6-\U0001f1ff" "]",
    flags=re.UNICODE,
)
_WHITESPACE = re.compile(r"[ \t]+")
_BLANK_LINES = re.compile(r"\n{2,}")
_PL_DIACRITICS = re.compile(r"[ąćęłńóśźż]", re.IGNORECASE)
_PL_WORD = re.compile(r"[a-ząćęłńóśźż]+", re.IGNORECASE)
_POLISH_WORDS = frozenset(
    {
        "jest",
        "nie",
        "tak",
        "czy",
        "jak",
        "dla",
        "się",
        "cześć",
        "dziękuję",
        "proszę",
        "dzień",
        "oraz",
        "przez",
        "ale",
        "lub",
        "albo",
        "może",
        "mam",
        "masz",
        "będzie",
        "być",
        "mogę",
        "chcę",
        "tego",
        "tej",
        "tym",
        "tych",
        "który",
        "która",
        "które",
        "gdzie",
        "kiedy",
        "dlaczego",
        "ponieważ",
        "bardzo",
        "dobrze",
        "dziś",
        "jutro",
        "wczoraj",
        "pogoda",
        "odpowiedź",
        "pytanie",
        "notatka",
        "notatki",
    }
)


def detect_speech_language(text: str, *, hint: str | None = None) -> str:
    """Best-effort ``pl`` | ``en`` for TTS voice selection."""
    lower = text.lower()
    if _PL_DIACRITICS.search(lower):
        return "pl"
    words = _PL_WORD.findall(lower)
    if words and sum(1 for w in words if w in _POLISH_WORDS) >= max(1, len(words) // 8):
        return "pl"
    hint_norm = (hint or "").lower()
    if hint_norm in ("pl", "en"):
        return hint_norm
    return "en"


def prepare_for_tts(text: str) -> str:
    """Strip markdown, code, URLs and emoji so the reply reads as spoken words."""
    out = _FENCED_CODE.sub(" ", text)
    out = _INLINE_CODE.sub(r"\1", out)
    out = _MD_LINK.sub(r"\1", out)
    out = _BARE_URL.sub(" ", out)
    out = _HEADING.sub("", out)
    out = _BLOCKQUOTE.sub("", out)
    out = _LIST_MARKER.sub("", out)
    out = _EMPHASIS.sub("", out)
    out = _EMOJI.sub("", out)
    out = _WHITESPACE.sub(" ", out)
    out = _BLANK_LINES.sub("\n", out)
    return out.strip()
