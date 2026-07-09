"""Ollama model presence checks and online provider wiring."""

from __future__ import annotations

import sys
from unittest.mock import MagicMock, patch

import pytest

from vesnai.config import Settings
from vesnai.providers.factory import build_providers
from vesnai.providers.fakes import FakeAIProvider, FakeEmbeddingProvider
from vesnai.providers.ollama import ensure_models, model_is_installed


@pytest.mark.parametrize(
    ("requested", "installed", "expected"),
    [
        ("qwen3.6", {"qwen3.6:latest"}, True),
        ("qwen3.6", {"bge-m3:latest"}, False),
        ("qwen3.5:122b-a10b", {"qwen3.5:9b"}, False),
        ("bge-m3", {"bge-m3:latest"}, True),
    ],
)
def test_model_is_installed(requested, installed, expected):
    assert model_is_installed(requested, installed) is expected


def test_ensure_models_pulls_only_missing():
    mock_client = MagicMock()
    mock_client.list.return_value = MagicMock(
        models=[MagicMock(model="qwen3.6:latest")]
    )
    mock_client.pull.return_value = iter([
        MagicMock(status="pulling manifest", completed=None, total=None),
        MagicMock(status="downloading", completed=50, total=100),
    ])

    fake_ollama = MagicMock()
    fake_ollama.Client.return_value = mock_client
    with patch.dict(sys.modules, {"ollama": fake_ollama}):
        ensure_models(["qwen3.6", "bge-m3"], host=None)

    mock_client.pull.assert_called_once_with("bge-m3", stream=True)


def test_build_providers_online_bootstraps_and_wires_real_providers():
    settings = Settings(offline_only=False)
    fake_ai = FakeAIProvider()
    fake_embed = FakeEmbeddingProvider()

    with (
        patch("vesnai.providers.factory.bootstrap_online_stack") as bootstrap,
        patch("vesnai.providers.ollama.OllamaAIProvider", return_value=fake_ai),
        patch("vesnai.providers.ollama.OllamaVisionProvider"),
        patch("vesnai.providers.ollama.OllamaEmbeddingProvider", return_value=fake_embed),
        patch("vesnai.providers.flux.MfluxImageProvider"),
        patch("vesnai.providers.whisper.WhisperCppSTTProvider"),
        patch("vesnai.providers.searxng.SearxngSearchProvider"),
    ):
        providers = build_providers(settings)

    bootstrap.assert_called_once()
    call_args, call_kwargs = bootstrap.call_args
    assert call_args[0] == settings
    assert "voice_store" in call_kwargs
    assert providers.ai is fake_ai
    assert providers.embedder is fake_embed
    assert providers.tts.__class__.__name__ == "UnavailableTTSProvider"


def test_build_providers_offline_skips_bootstrap():
    settings = Settings(offline_only=True)
    with patch("vesnai.providers.factory.bootstrap_online_stack") as bootstrap:
        providers = build_providers(settings)
    bootstrap.assert_not_called()
    assert providers.ai.__class__.__name__ == "FakeAIProvider"
