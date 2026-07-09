"""Build the active provider set from settings.

Offline mode (default) uses deterministic fakes. Online mode bootstraps only
the components enabled in the config (per-component, not all-or-nothing) and
wires **only** real providers — no silent fallback to fakes. Components set to
``none`` get explicit disabled providers with actionable error messages.
"""

from __future__ import annotations

from vesnai.ai.vectorstore import InMemoryVectorStore, QdrantVectorStore, VectorStore
from vesnai.app_state import Providers, default_fake_providers
from vesnai.config import Settings, resolve_secret_ref
from vesnai.observability import get_logger
from vesnai.providers.base import ImageProvider, SearchProvider, STTProvider
from vesnai.runtime.bootstrap import bootstrap_online_stack
from vesnai.secrets import SecretStore
from vesnai.voice_registration import VoiceRegistrationStore

log = get_logger("vesnai.providers.factory")

LLM_SECRET_NAME = "llm"


def build_vector_store(settings: Settings, *, dim: int) -> VectorStore:
    if settings.resolved_vector_store() == "in_memory":
        return InMemoryVectorStore()
    return QdrantVectorStore(dim, url=settings.qdrant_url)


def _resolve_llm_api_key(settings: Settings, secrets: SecretStore | None) -> str | None:
    key = resolve_secret_ref(settings.llm_api_key)
    if key:
        return key
    if secrets is not None:
        return secrets.get(LLM_SECRET_NAME)
    return None


def _build_llm_providers(settings: Settings, secrets: SecretStore | None) -> dict:
    """Build ai/reasoning/marena/vision/embedder for the configured provider."""
    if settings.llm_provider == "openai_compatible":
        from vesnai.providers.openai_compat import (
            OpenAICompatAIProvider,
            OpenAICompatEmbeddingProvider,
            OpenAICompatVisionProvider,
        )

        base_url = (settings.llm_base_url or "").rstrip("/")
        if not base_url:
            raise ValueError(
                "llm.provider is openai_compatible but llm.base_url is not set "
                "(e.g. https://api.openai.com/v1)"
            )
        api_key = _resolve_llm_api_key(settings, secrets)
        log.info(
            "llm_provider_selected",
            provider="openai_compatible",
            base_url=base_url,
            note="note content is sent to this endpoint",
        )

        def ai(model: str, think: bool) -> OpenAICompatAIProvider:
            return OpenAICompatAIProvider(
                model=model,
                base_url=base_url,
                api_key=api_key,
                think=think,
                timeout=settings.ollama_request_timeout_seconds,
            )

        return {
            "ai": ai(settings.default_chat_model, settings.chat_thinking),
            "reasoning": ai(settings.default_reasoning_model, settings.reasoning_thinking),
            "marena": ai(settings.resolved_marena_model, settings.resolved_marena_thinking),
            "vision": OpenAICompatVisionProvider(
                model=settings.default_vision_model,
                base_url=base_url,
                api_key=api_key,
                timeout=settings.ollama_request_timeout_seconds,
            ),
            "embedder": OpenAICompatEmbeddingProvider(
                model=settings.default_embedding_model,
                base_url=base_url,
                api_key=api_key,
                dim=settings.embedding_dim,
                timeout=settings.ollama_request_timeout_seconds,
            ),
        }

    if settings.llm_provider != "ollama":
        raise ValueError(
            f"unknown llm.provider {settings.llm_provider!r} "
            "(expected ollama | openai_compatible)"
        )

    from vesnai.providers.ollama import (
        OllamaAIProvider,
        OllamaEmbeddingProvider,
        OllamaVisionProvider,
    )

    def ollama_ai(model: str, think: bool) -> OllamaAIProvider:
        return OllamaAIProvider(
            model=model,
            host=settings.ollama_host,
            think=think,
            keep_alive=settings.ollama_keep_alive,
            timeout=settings.ollama_request_timeout_seconds,
        )

    return {
        "ai": ollama_ai(settings.default_chat_model, settings.chat_thinking),
        "reasoning": ollama_ai(settings.default_reasoning_model, settings.reasoning_thinking),
        "marena": ollama_ai(settings.resolved_marena_model, settings.resolved_marena_thinking),
        "vision": OllamaVisionProvider(
            model=settings.default_vision_model,
            host=settings.ollama_host,
            keep_alive=settings.ollama_keep_alive,
            timeout=settings.ollama_request_timeout_seconds,
        ),
        "embedder": OllamaEmbeddingProvider(
            model=settings.default_embedding_model,
            dim=settings.embedding_dim,
            host=settings.ollama_host,
            timeout=settings.ollama_request_timeout_seconds,
        ),
    }


def _build_legacy_tts(settings: Settings):
    from vesnai.providers.chatterbox import ChatterboxTTSProvider

    reference = settings.resolved_tts_reference_wav
    log.info("tts_engine_selected", engine="chatterbox", reference=str(reference))
    return ChatterboxTTSProvider(
        reference,
        exaggeration=settings.tts_exaggeration,
        cfg_weight=settings.tts_cfg_weight,
        temperature=settings.tts_temperature,
        repetition_penalty=settings.tts_repetition_penalty,
    )


def _build_tts(
    settings: Settings,
    *,
    secrets: SecretStore | None = None,
    voice_store: VoiceRegistrationStore | None = None,
):
    if settings.tts_engine == "chatterbox":
        return _build_legacy_tts(settings)

    from vesnai.providers.remote_tts import RemoteTTSProvider, UnavailableTTSProvider

    if settings.tts_engine == "none":
        log.info("tts_engine_selected", engine="none")
        return UnavailableTTSProvider()

    store = voice_store or VoiceRegistrationStore(settings.data_dir)
    if secrets is None:
        return UnavailableTTSProvider()
    log.info(
        "tts_engine_selected",
        engine="remote",
        configured=store.is_configured(),
    )
    return RemoteTTSProvider(store, secrets)


def _seed_voice_registration(
    settings: Settings,
    *,
    secrets: SecretStore | None,
    voice_store: VoiceRegistrationStore,
) -> None:
    """Seed voice.json from the yaml ``tts:`` section on first start only.

    The app's runtime registration (PUT /v1/settings/voice) is the source of
    truth once it exists; the yaml never overwrites it.
    """
    from vesnai.voice_registration import (
        DEFAULT_SECRET_NAME,
        PROVIDER_OPENAI,
        PROVIDER_SIDECAR,
        VoiceRegistration,
    )

    if settings.tts_engine != "remote" or settings.tts_seed_provider is None:
        return
    if voice_store.is_configured():
        return
    if secrets is None:
        return
    provider = settings.tts_seed_provider
    if provider not in (PROVIDER_SIDECAR, PROVIDER_OPENAI):
        raise ValueError(f"vesnai.yaml: unknown tts.mode {provider!r}")
    api_key = resolve_secret_ref(settings.tts_api_key)
    if not api_key:
        log.warning(
            "tts_seed_skipped",
            reason="tts.api_key missing (set it or register from the app)",
        )
        return
    voices = dict(settings.tts_voices or {})
    if provider == PROVIDER_SIDECAR and (not settings.tts_url or not voices):
        log.warning(
            "tts_seed_skipped",
            reason="sidecar seeding needs tts.url and tts.voices in vesnai.yaml",
        )
        return
    if provider == PROVIDER_OPENAI and not voices:
        voices = {"pl": "nova", "en": "nova"}
    secrets.set(DEFAULT_SECRET_NAME, api_key)
    voice_store.save(
        VoiceRegistration(
            provider=provider,
            url=(settings.tts_url or "").rstrip("/"),
            voices=voices,
            model=settings.tts_model,
        )
    )
    log.info("tts_seeded_from_config", provider=provider)


def build_providers(
    settings: Settings,
    *,
    secrets: SecretStore | None = None,
    voice_store: VoiceRegistrationStore | None = None,
) -> Providers:
    if settings.offline_only:
        log.info("providers_offline_mode", detail="using deterministic fake providers")
        return default_fake_providers()

    store = voice_store or VoiceRegistrationStore(settings.data_dir)
    _seed_voice_registration(settings, secrets=secrets, voice_store=store)
    bootstrap_online_stack(settings, voice_store=store)

    llm = _build_llm_providers(settings, secrets)

    image: ImageProvider
    if settings.image_engine == "flux":
        from vesnai.providers.flux import MfluxImageProvider

        image = MfluxImageProvider(
            model=settings.flux_model,
            base_model=settings.flux_base_model,
            quantize=settings.flux_quantize,
        )
    else:
        from vesnai.providers.disabled import DisabledImageProvider

        image = DisabledImageProvider()

    stt: STTProvider
    if settings.stt_engine == "whisper":
        from vesnai.providers.whisper import WhisperCppSTTProvider

        stt = WhisperCppSTTProvider(
            settings.resolved_whisper_model_path,
            binary=settings.whisper_binary,
        )
    else:
        from vesnai.providers.disabled import DisabledSTTProvider

        stt = DisabledSTTProvider()

    search: SearchProvider
    if settings.search_engine == "searxng":
        from vesnai.providers.searxng import SearxngSearchProvider

        search = SearxngSearchProvider(base_url=settings.searxng_url)
    else:
        from vesnai.providers.disabled import DisabledSearchProvider

        search = DisabledSearchProvider()

    providers = Providers(
        ai=llm["ai"],
        reasoning=llm["reasoning"],
        marena=llm["marena"],
        vision=llm["vision"],
        embedder=llm["embedder"],
        image=image,
        tts=_build_tts(settings, secrets=secrets, voice_store=store),
        stt=stt,
        search=search,
    )
    log.info(
        "providers_online_enabled",
        llm_provider=settings.llm_provider,
        chat=settings.default_chat_model,
        reasoning=settings.default_reasoning_model,
        marena=settings.resolved_marena_model,
        vision=settings.default_vision_model,
        embeddings=settings.default_embedding_model,
        vector_store=settings.resolved_vector_store(),
        search=settings.search_engine,
        image=settings.image_engine,
        stt=settings.stt_engine,
    )
    return providers
