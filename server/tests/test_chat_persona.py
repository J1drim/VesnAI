"""Tests for chat system prompt and feminine Polish persona."""

from __future__ import annotations

from vesnai.ai.chat import build_system_content


def test_polish_system_prompt_uses_feminine_persona():
    content = build_system_content(rag="(none)", memory_block="", language="pl")
    assert "asystentką" in content
    assert "mogłam" in content
    assert "unikaj form męskich" in content


def test_english_system_prompt():
    content = build_system_content(rag="(none)", memory_block="", language="en")
    assert "Always reply in English" in content
    assert "asystentką" not in content
