"""vesnai.yaml loading: nested mapping, precedence, and role fallbacks."""

from __future__ import annotations

from pathlib import Path

import pytest

from vesnai.config import Settings, load_config_file, set_config_file


@pytest.fixture(autouse=True)
def _reset_config_override():
    yield
    set_config_file(None)


def _write(tmp_path: Path, text: str) -> Path:
    path = tmp_path / "vesnai.yaml"
    path.write_text(text)
    return path


def test_yaml_maps_nested_sections_to_settings(tmp_path):
    path = _write(
        tmp_path,
        """
paths:
  knowledge: /kb
  data: /state
network:
  host: 0.0.0.0
  port: 9000
  tls: { enabled: false }
offline_only: false
llm:
  provider: openai_compatible
  base_url: https://api.example.com/v1
  models:
    chat: { model: gpt-x, thinking: false }
    reasoning: { model: gpt-y, thinking: true }
    marena: { model: gpt-critic, thinking: false }
    vision: gpt-v
    embeddings: { model: embed-1, dim: 512 }
tts: { mode: none }
stt: { mode: none }
image: { mode: none }
vector_store: { kind: in_memory }
search: { mode: none }
""",
    )
    set_config_file(path)
    s = Settings()
    assert s.knowledge_dir == Path("/kb")
    assert s.data_dir == Path("/state")
    assert s.host == "0.0.0.0"
    assert s.port == 9000
    assert s.tls_enabled is False
    assert s.offline_only is False
    assert s.llm_provider == "openai_compatible"
    assert s.llm_base_url == "https://api.example.com/v1"
    assert s.default_chat_model == "gpt-x"
    assert s.default_reasoning_model == "gpt-y"
    assert s.reasoning_thinking is True
    assert s.resolved_marena_model == "gpt-critic"
    assert s.resolved_marena_thinking is False
    assert s.default_vision_model == "gpt-v"
    assert s.default_embedding_model == "embed-1"
    assert s.embedding_dim == 512
    assert s.tts_engine == "none"
    assert s.stt_engine == "none"
    assert s.image_engine == "none"
    assert s.resolved_vector_store() == "in_memory"
    assert s.search_engine == "none"


def test_env_overrides_yaml(tmp_path, monkeypatch):
    path = _write(tmp_path, "network: { port: 9000 }\n")
    set_config_file(path)
    monkeypatch.setenv("VESNAI_PORT", "9500")
    assert Settings().port == 9500


def test_init_kwargs_override_env_and_yaml(tmp_path, monkeypatch):
    path = _write(tmp_path, "network: { port: 9000 }\n")
    set_config_file(path)
    monkeypatch.setenv("VESNAI_PORT", "9500")
    assert Settings(port=9999).port == 9999


def test_marena_defaults_to_reasoning_role(tmp_path):
    path = _write(
        tmp_path,
        "llm:\n  models:\n    reasoning: { model: big-model, thinking: true }\n",
    )
    set_config_file(path)
    s = Settings()
    assert s.resolved_marena_model == "big-model"
    assert s.resolved_marena_thinking is True


def test_tts_seed_fields_from_yaml(tmp_path):
    path = _write(
        tmp_path,
        """
tts:
  mode: sidecar
  url: http://tts.local:59125
  api_key: env:MY_TTS_KEY
  voices: { pl: voice-pl, en: voice-en }
""",
    )
    set_config_file(path)
    s = Settings()
    assert s.tts_engine == "remote"
    assert s.tts_seed_provider == "sidecar"
    assert s.tts_url == "http://tts.local:59125"
    assert s.tts_voices == {"pl": "voice-pl", "en": "voice-en"}


def test_unknown_mode_values_fail_fast(tmp_path):
    path = _write(tmp_path, "tts: { mode: kokoro }\n")
    with pytest.raises(ValueError, match="tts.mode"):
        load_config_file(path)


def test_missing_yaml_file_is_fine(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)  # no vesnai.yaml here
    assert Settings().port == 8443


def test_cloud_example_yaml_loads():
    from pathlib import Path

    path = Path(__file__).resolve().parents[1] / "vesnai.cloud.example.yaml"
    set_config_file(path)
    s = Settings()
    assert s.offline_only is False
    assert s.llm_provider == "openai_compatible"
    assert s.tts_engine == "none"
    assert s.image_engine == "none"
    assert s.stt_engine == "none"
    assert s.search_engine == "none"
    assert s.vector_store == "in_memory"
    assert s.marena_enabled is False
