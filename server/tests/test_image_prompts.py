"""Tests for FLUX image prompt builders."""

from __future__ import annotations

from vesnai.ai.image_prompts import build_chat_image_prompt, build_memory_image_prompt


def test_memory_prompt_includes_subject_and_style():
    prompt = build_memory_image_prompt("Aurora trip", "see the northern lights")
    assert "Aurora trip" in prompt
    assert "see the northern lights" in prompt
    assert "abstract" in prompt.lower()
    assert "vintage" in prompt.lower()
    assert "risograph" in prompt.lower()
    assert "not photorealistic" in prompt.lower()


def test_memory_prompt_trims_long_body():
    body = "word " * 200
    prompt = build_memory_image_prompt("Title", body)
    assert len(prompt) < len(body)


def test_chat_prompt_preserves_user_text_first():
    user = "a cozy reading nook with plants"
    prompt = build_chat_image_prompt(user)
    assert prompt.startswith(user)
    assert "vintage editorial illustration" in prompt


def test_chat_prompt_empty_user():
    prompt = build_chat_image_prompt("   ")
    assert "vintage editorial illustration" in prompt
