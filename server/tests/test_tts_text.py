"""Tests for the TTS text cleanup that runs before speech synthesis."""

from __future__ import annotations

from vesnai.ai.tts_text import detect_speech_language, prepare_for_tts


def test_strips_markdown_emphasis_and_lists():
    text = "**Plan na dziś:**\n- kup mleko\n- zadzwoń do mamy"
    assert prepare_for_tts(text) == "Plan na dziś:\nkup mleko\nzadzwoń do mamy"


def test_removes_code_fences_and_inline_code():
    text = "Uruchom `pytest` tak:\n```bash\nuv run pytest\n```\nGotowe."
    cleaned = prepare_for_tts(text)
    assert "uv run pytest" not in cleaned
    assert "pytest" in cleaned
    assert "```" not in cleaned and "`" not in cleaned


def test_keeps_link_label_drops_url():
    assert prepare_for_tts("Zobacz [dokumentację](https://example.com/docs)") == (
        "Zobacz dokumentację"
    )


def test_drops_bare_urls_and_emoji():
    cleaned = prepare_for_tts("Cześć 😊 odwiedź https://vesnai.ai teraz")
    assert "https" not in cleaned
    assert "😊" not in cleaned
    assert "Cześć" in cleaned and "teraz" in cleaned


def test_blank_input_returns_empty():
    assert prepare_for_tts("   \n\n  ") == ""


def test_detect_speech_language_polish_diacritics():
    assert detect_speech_language("Plan na dziś wygląda dobrze.") == "pl"


def test_detect_speech_language_polish_words_without_diacritics():
    assert detect_speech_language("To jest odpowiedz na twoje pytanie.") == "pl"


def test_detect_speech_language_english():
    assert detect_speech_language("Here is the answer to your question.") == "en"


def test_detect_speech_language_prefers_text_over_english_hint():
    assert detect_speech_language("Dziś pogoda jest ładna.", hint="en") == "pl"
