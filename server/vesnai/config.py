"""Typed application configuration (file + env + CLI overrides).

Precedence (lowest to highest): ``vesnai.yaml`` < environment variables < CLI.
Environment variables are prefixed ``VESNAI_`` (e.g. ``VESNAI_KNOWLEDGE_DIR``).
The config file is found via ``--config``, ``$VESNAI_CONFIG``, or a
``vesnai.yaml`` next to the current working directory (see
:func:`find_config_file`); ``vesnai.example.yaml`` documents every section.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import yaml
from pydantic import Field
from pydantic_settings import (
    BaseSettings,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
)

# Set by the CLI (--config) before Settings() is constructed; None means
# "discover automatically" via find_config_file().
_config_file_override: Path | None = None


def set_config_file(path: Path | None) -> None:
    global _config_file_override
    _config_file_override = path


def find_config_file() -> Path | None:
    """Locate vesnai.yaml: explicit override > $VESNAI_CONFIG > ./vesnai.yaml."""
    if _config_file_override is not None:
        return _config_file_override
    env = os.environ.get("VESNAI_CONFIG")
    if env:
        return Path(env)
    cwd_candidate = Path("vesnai.yaml")
    if cwd_candidate.exists():
        return cwd_candidate
    return None


def resolve_secret_ref(value: str | None) -> str | None:
    """Resolve ``env:NAME`` references so keys never need to live in the yaml."""
    if value and value.startswith("env:"):
        return os.environ.get(value[4:]) or None
    return value


def _flatten_config(data: dict[str, Any]) -> dict[str, Any]:
    """Map the nested vesnai.yaml sections onto flat Settings field names."""
    out: dict[str, Any] = {}

    def put(field: str, value: Any) -> None:
        if value is not None:
            out[field] = value

    paths = data.get("paths") or {}
    put("knowledge_dir", paths.get("knowledge"))
    put("data_dir", paths.get("data"))
    put("models_cache_dir", paths.get("models_cache"))

    network = data.get("network") or {}
    put("host", network.get("host"))
    put("port", network.get("port"))
    put("advertise_mdns", network.get("mdns"))
    tls = network.get("tls") or {}
    put("tls_enabled", tls.get("enabled"))
    put("tls_cert_file", tls.get("cert"))
    put("tls_key_file", tls.get("key"))

    put("offline_only", data.get("offline_only"))

    llm = data.get("llm") or {}
    put("llm_provider", llm.get("provider"))
    put("llm_base_url", llm.get("base_url"))
    put("llm_api_key", llm.get("api_key"))
    models = llm.get("models") or {}

    def role(name: str, model_field: str, thinking_field: str | None) -> None:
        spec = models.get(name)
        if spec is None:
            return
        if isinstance(spec, str):
            put(model_field, spec)
            return
        put(model_field, spec.get("model"))
        if thinking_field is not None:
            put(thinking_field, spec.get("thinking"))
        if name == "embeddings":
            put("embedding_dim", spec.get("dim"))

    role("chat", "default_chat_model", "chat_thinking")
    role("reasoning", "default_reasoning_model", "reasoning_thinking")
    role("marena", "marena_model", "marena_thinking")
    role("vision", "default_vision_model", None)
    role("embeddings", "default_embedding_model", None)
    ollama = llm.get("ollama") or {}
    put("ollama_host", ollama.get("host"))
    put("ollama_keep_alive", ollama.get("keep_alive"))
    put("ollama_auto_pull", ollama.get("auto_pull"))

    tts = data.get("tts") or {}
    mode = tts.get("mode")
    if mode is not None:
        if mode == "none":
            put("tts_engine", "none")
        elif mode == "chatterbox":
            put("tts_engine", "chatterbox")
        elif mode in ("sidecar", "openai"):
            # Registration-based providers: yaml only seeds voice.json on
            # first start (runtime PUT /v1/settings/voice always wins).
            put("tts_engine", "remote")
            put("tts_seed_provider", mode)
            put("tts_url", tts.get("url"))
            put("tts_api_key", tts.get("api_key"))
            put("tts_model", tts.get("model"))
            put("tts_voices", tts.get("voices"))
        else:
            raise ValueError(
                f"vesnai.yaml: unknown tts.mode {mode!r} "
                "(expected none | sidecar | openai | chatterbox)"
            )
    chatterbox = tts.get("chatterbox") or {}
    put("tts_reference_wav", chatterbox.get("reference_wav"))
    put("tts_exaggeration", chatterbox.get("exaggeration"))
    put("tts_cfg_weight", chatterbox.get("cfg_weight"))
    put("tts_temperature", chatterbox.get("temperature"))
    put("tts_repetition_penalty", chatterbox.get("repetition_penalty"))

    stt = data.get("stt") or {}
    stt_mode = stt.get("mode")
    if stt_mode is not None:
        if stt_mode not in ("whisper", "none"):
            raise ValueError(
                f"vesnai.yaml: unknown stt.mode {stt_mode!r} (expected whisper | none)"
            )
        put("stt_engine", stt_mode)
    put("stt_model", stt.get("model"))
    put("whisper_binary", stt.get("binary"))
    put("whisper_model_path", stt.get("model_path"))

    image = data.get("image") or {}
    image_mode = image.get("mode")
    if image_mode is not None:
        if image_mode not in ("flux", "none"):
            raise ValueError(
                f"vesnai.yaml: unknown image.mode {image_mode!r} (expected flux | none)"
            )
        put("image_engine", image_mode)
    put("flux_model", image.get("model"))
    put("flux_base_model", image.get("base_model"))
    if "quantize" in image:
        put("flux_quantize", image.get("quantize"))
    put("hf_token", image.get("hf_token"))
    put("auto_illustrate", image.get("auto_illustrate"))

    vector = data.get("vector_store") or {}
    put("vector_store", vector.get("kind"))
    put("qdrant_url", vector.get("url"))

    search = data.get("search") or {}
    search_mode = search.get("mode")
    if search_mode is not None:
        if search_mode not in ("searxng", "none"):
            raise ValueError(
                f"vesnai.yaml: unknown search.mode {search_mode!r} (expected searxng | none)"
            )
        put("search_engine", search_mode)
    put("searxng_url", search.get("url"))
    put("search_max_seconds", search.get("max_seconds"))
    put("search_languages", search.get("languages"))

    memory = data.get("memory") or {}
    put("memory_disk_max_chars", memory.get("disk_max_chars"))
    put("memory_prompt_max_chars", memory.get("prompt_max_chars"))
    put("memory_review_interval_turns", memory.get("review_interval_turns"))

    marena = data.get("marena") or {}
    put("marena_enabled", marena.get("enabled"))
    put("marena_interval_hours", marena.get("interval_hours"))
    put("marena_max_notes_per_run", marena.get("max_notes_per_run"))
    put("marena_web_search", marena.get("web_search"))

    return out


def load_config_file(path: Path) -> dict[str, Any]:
    raw = yaml.safe_load(path.read_text()) or {}
    if not isinstance(raw, dict):
        raise ValueError(f"{path}: top level of vesnai.yaml must be a mapping")
    return _flatten_config(raw)


class _YamlConfigSource(PydanticBaseSettingsSource):
    """Lowest-priority settings source backed by vesnai.yaml."""

    def __init__(self, settings_cls: type[BaseSettings]) -> None:
        super().__init__(settings_cls)
        path = find_config_file()
        self._values: dict[str, Any] = (
            load_config_file(path) if path is not None and path.exists() else {}
        )

    def get_field_value(self, field: Any, field_name: str) -> tuple[Any, str, bool]:
        return self._values.get(field_name), field_name, False

    def __call__(self) -> dict[str, Any]:
        return dict(self._values)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="VESNAI_",
        env_file=".env",
        extra="ignore",
    )

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        # Highest priority first: CLI/init > env > .env > vesnai.yaml.
        return (
            init_settings,
            env_settings,
            dotenv_settings,
            file_secret_settings,
            _YamlConfigSource(settings_cls),
        )

    # Storage
    knowledge_dir: Path = Field(
        default=Path("./knowledge"),
        description="Directory holding the OKF bundle (the source of truth).",
    )
    data_dir: Path = Field(
        default=Path("./data"),
        description="Directory for derived indexes, secrets and runtime state.",
    )
    models_cache_dir: Path = Field(default=Path("./models"))

    # Network
    host: str = "127.0.0.1"
    port: int = 8443
    advertise_mdns: bool = True
    service_name: str = "VesnAI"

    # TLS
    tls_enabled: bool = True
    tls_cert_file: Path | None = None
    tls_key_file: Path | None = None

    # Privacy / models
    offline_only: bool = Field(
        default=True,
        description="When true, never call external APIs even if keys are configured.",
    )

    # LLM provider: "ollama" (local) or "openai_compatible" (OpenAI, OpenRouter,
    # vLLM, llama.cpp server, LM Studio, …). openai_compatible sends note
    # content to whatever endpoint llm_base_url points at.
    llm_provider: str = "ollama"
    llm_base_url: str | None = None  # e.g. https://api.openai.com/v1
    llm_api_key: str | None = None  # literal, or "env:NAME", or secrets-store "llm" entry

    # Local model roles (tuned for Apple Silicon, 64 GB). The Qwen3.6 35B-A3B MoE
    # serves both fast chat (thinking off) and deeper reasoning (thinking on) from
    # one resident set of weights, so no model swap or double RAM is needed.
    default_chat_model: str = "qwen3.6"
    chat_thinking: bool = False  # snappy tool-calling for interactive chat/voice
    default_reasoning_model: str = "qwen3.6"  # override e.g. "qwen3.5:122b-a10b" for max quality
    reasoning_thinking: bool = True  # deeper reasoning for background jobs
    default_vision_model: str = "qwen3.6"  # multimodal (mmproj) for photo captioning
    default_embedding_model: str = "bge-m3"  # 1024-dim, multilingual (PL + EN)
    embedding_dim: int = 1024
    # Marena (adversarial critic) model; None inherits the reasoning role.
    marena_model: str | None = None
    marena_thinking: bool | None = None

    # Speech-to-text: "whisper" (local whisper.cpp) or "none" (skip bootstrap;
    # the app's on-device STT still works — this only disables server-side
    # transcription of uploaded audio).
    stt_engine: str = "whisper"
    stt_model: str = "large-v3"  # whisper.cpp (MIT)

    # Image generation: "flux" (local mflux) or "none".
    image_engine: str = "flux"
    # HuggingFace token for the gated official FLUX repo (literal or "env:NAME").
    hf_token: str | None = None

    # Vector store: "auto" (qdrant when online, in-memory when offline),
    # "qdrant", or "in_memory".
    vector_store: str = "auto"

    # Web search: "searxng" or "none".
    search_engine: str = "searxng"

    # FLUX image generation via the isolated mflux CLI. Defaults to the official
    # black-forest-labs/FLUX.1-schnell repo, which is gated on HuggingFace and
    # needs `huggingface-cli login` (or HF_TOKEN) once. For a no-auth setup,
    # point flux_model at an ungated mflux mirror, e.g.
    # flux_model="dhairyashil/FLUX.1-schnell-mflux-4bit", flux_base_model="schnell",
    # flux_quantize=None (the mirror is already 4-bit quantized).
    # flux_model: HF repo id, builtin name (schnell/dev), or local path.
    flux_model: str = "schnell"
    # flux_base_model: --base-model when flux_model is a third-party repo/path.
    flux_base_model: str | None = None
    # flux_quantize: -q value; None skips re-quantizing a pre-quantized mirror.
    flux_quantize: int | None = 8

    # Auto-illustration: generate a FLUX memory-aid image for every new text note.
    auto_illustrate: bool = Field(
        default=True,
        description="Generate a FLUX image for each new text note (queued in the background).",
    )

    # Text-to-speech. Default is a registered external voice service (see voice.json).
    # The optional in-process engine is VESNAI_TTS_ENGINE=chatterbox (MIT);
    # "none" disables TTS entirely (Speak returns 503).
    # BREAKING: the GPL-chained "kokoro" engine was removed; VESNAI_TTS_ENGINE=kokoro
    # is no longer accepted — use "chatterbox" or register an external service.
    tts_engine: str = "remote"  # "remote" | "chatterbox" | "none"
    # First-start seed for the voice registration, from the yaml tts: section.
    # Only applied when no voice.json exists yet; the app's runtime
    # PUT /v1/settings/voice always wins afterwards.
    tts_seed_provider: str | None = None  # "sidecar" | "openai"
    tts_url: str | None = None
    tts_api_key: str | None = None  # literal or "env:NAME"
    tts_model: str | None = None
    tts_voices: dict[str, str] | None = None
    tts_reference_wav: Path | None = None  # Chatterbox speaker clip; defaults to bundled CC0 clip
    # Chatterbox inference controls. Defaults are tuned for clear Polish: a lower
    # exaggeration keeps speech from rushing, cfg_weight matches the library
    # default (was hardcoded to 0.0), and a slightly lower temperature steadies
    # articulation. All are overridable via VESNAI_TTS_* env vars.
    tts_exaggeration: float = 0.35  # Chatterbox expressiveness (lower = steadier)
    tts_cfg_weight: float = 0.3  # Classifier-free guidance weight
    tts_temperature: float = 0.4  # Sampling temperature (lower = clearer)
    tts_repetition_penalty: float = 2.0  # Discourages repeated speech tokens

    # Ollama runtime
    ollama_host: str | None = None
    ollama_keep_alive: str = "30m"
    ollama_auto_pull: bool = Field(
        default=True,
        description="When online, pull any missing Ollama models on startup.",
    )

    # Online stack service URLs
    qdrant_url: str = "http://127.0.0.1:6333"
    searxng_url: str = "http://127.0.0.1:8888"
    bootstrap_timeout_seconds: int = 180

    # whisper.cpp (STT)
    whisper_binary: str | None = None  # auto-detect whisper-cli / whisper-cpp
    whisper_model_path: Path | None = None  # default: models_cache_dir / ggml-{stt_model}.bin

    # Search agent defaults
    search_max_seconds: int = 60
    search_languages: list[str] = Field(default_factory=lambda: ["en", "pl"])

    # Durable memory (Hermes-style split files)
    memory_disk_max_chars: int = Field(
        default=100_000,
        description="Max total chars stored across memory.md, user.md, projects.md.",
    )
    memory_prompt_max_chars: int = Field(
        default=32_000,
        description="Max chars of memory injected into the chat system prompt.",
    )
    memory_review_interval_turns: int = Field(
        default=10,
        description="Background memory review after this many user turns without update_memory.",
    )
    chat_turn_validation: bool = Field(
        default=True,
        description="After each chat turn, use the reasoning model to audit missing tool actions.",
    )
    tool_policy_review_interval_hours: float = Field(
        default=24,
        description="Run idle tool policy review at most this often (hours).",
    )
    tool_policy_review_min_failures: int = Field(
        default=3,
        description="Minimum audit failures in trajectories before policy review runs.",
    )

    # Marena — idle adversarial critic of new/modified user notes
    marena_enabled: bool = Field(
        default=True,
        description="Run the Marena critic over new/modified user notes when idle.",
    )
    marena_interval_hours: float = Field(
        default=6,
        description="Run the Marena review at most this often (hours).",
    )
    marena_max_notes_per_run: int = Field(
        default=3,
        description="Max notes Marena critiques per run.",
    )
    marena_web_search: bool = Field(
        default=True,
        description="Let Marena search the web for competing references (needs online stack).",
    )

    chat_history_max_messages: int = Field(
        default=5,
        description="Max prior chat messages sent to the LLM (full transcript stays on disk).",
    )
    chat_turn_timeout_seconds: int = Field(
        default=600,
        description="Wall-clock limit for one async chat turn before failing it.",
    )
    ollama_request_timeout_seconds: float = Field(
        default=300.0,
        description="HTTP timeout for Ollama chat/generate/embed requests.",
    )
    stale_assistant_message_minutes: float = Field(
        default=10.0,
        description="On startup, fail assistant placeholders empty longer than this.",
    )

    def ensure_dirs(self) -> None:
        for d in (self.knowledge_dir, self.data_dir, self.models_cache_dir):
            Path(d).mkdir(parents=True, exist_ok=True)

    def public_base_url(self) -> str:
        """Best-effort URL a LAN client should use to reach this server.

        When the server binds a loopback/wildcard address we substitute the
        machine's LAN IP so a phone can actually connect.
        """
        from vesnai.discovery import lan_ip

        scheme = "https" if self.tls_enabled else "http"
        host = self.host
        if host in ("0.0.0.0", "127.0.0.1", "::", "localhost"):
            host = lan_ip()
        return f"{scheme}://{host}:{self.port}"

    @property
    def resolved_marena_model(self) -> str:
        """Marena's dedicated model, defaulting to the reasoning role."""
        return self.marena_model or self.default_reasoning_model

    @property
    def resolved_marena_thinking(self) -> bool:
        if self.marena_thinking is not None:
            return self.marena_thinking
        return self.reasoning_thinking

    @property
    def resolved_hf_token(self) -> str | None:
        return resolve_secret_ref(self.hf_token)

    def resolved_vector_store(self) -> str:
        if self.vector_store == "auto":
            return "in_memory" if self.offline_only else "qdrant"
        return self.vector_store

    @property
    def resolved_whisper_model_path(self) -> Path:
        if self.whisper_model_path is not None:
            return self.whisper_model_path
        return self.models_cache_dir / f"ggml-{self.stt_model}.bin"

    @property
    def resolved_tts_reference_wav(self) -> Path:
        if self.tts_reference_wav is not None:
            return self.tts_reference_wav
        return (
            Path(__file__).resolve().parent.parent
            / "assets"
            / "voices"
            / "vesna_pl_young_female.wav"
        )


_settings: Settings | None = None


def get_settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings


def set_settings(settings: Settings) -> None:
    """Override settings (used by the CLI and tests)."""
    global _settings
    _settings = settings
