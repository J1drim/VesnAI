"""Start and verify the local AI stack for online mode — per component.

Online mode never falls back to fake providers, but it also only bootstraps
what the config actually enables: a cloud-LLM-only setup with
``tts: none, image: none, vector_store: in_memory, search: none`` needs no
Docker and no Ollama. Inside a container the bootstrap never shells out
(no docker/brew/ollama-serve): services must be provided by compose (see the
``ollama`` service and ``VESNAI_OLLAMA_HOST``), and whisper/image are
host-mode features.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import time
from pathlib import Path

import httpx

from vesnai.config import Settings
from vesnai.observability import get_logger
from vesnai.runtime.mflux_cli import find_mflux_generate, install_mflux_tool
from vesnai.voice_registration import VoiceRegistrationStore

log = get_logger("vesnai.runtime.bootstrap")

SERVER_ROOT = Path(__file__).resolve().parents[2]
COMPOSE_FILE = SERVER_ROOT / "docker-compose.yml"


class BootstrapError(RuntimeError):
    """Raised when a required online dependency cannot be started."""


def running_in_container() -> bool:
    return Path("/.dockerenv").exists() or Path("/run/.containerenv").exists()


def bootstrap_online_stack(
    settings: Settings, *, voice_store: VoiceRegistrationStore | None = None
) -> None:
    in_container = running_in_container()
    log.info("bootstrap_online_start", in_container=in_container)
    _ensure_python_ai_packages(settings)
    if settings.tts_engine == "chatterbox":
        _ensure_tts_reference(settings)

    if settings.image_engine == "flux":
        if in_container:
            raise BootstrapError(
                "FLUX image generation is a host-mode feature and is not "
                "available inside the Docker container. Set image.mode: none "
                "(or VESNAI_IMAGE_ENGINE=none) for the containerized server, "
                "or run the server on the host."
            )
        _ensure_mflux_cli()

    # Docker-backed sidecars, only for the components that need them.
    compose_services: list[str] = []
    if settings.resolved_vector_store() == "qdrant":
        compose_services.append("qdrant")
    if settings.search_engine == "searxng":
        compose_services.append("searxng")
    if compose_services:
        if not in_container:
            # On the host we start the sidecars ourselves.
            _ensure_docker(settings)
            _compose_up(compose_services, settings=settings)
        # In a container the services come from the same compose file; either
        # way, wait until they answer.
        if "qdrant" in compose_services:
            _wait_for_http(f"{settings.qdrant_url.rstrip('/')}/healthz", name="Qdrant")
        if "searxng" in compose_services:
            _wait_for_searxng(settings.searxng_url)

    if settings.llm_provider == "ollama":
        _ensure_ollama(settings, in_container=in_container)
        if settings.ollama_auto_pull:
            from vesnai.providers.ollama import ensure_models

            ensure_models(
                list(
                    dict.fromkeys(
                        [
                            settings.default_chat_model,
                            settings.default_reasoning_model,
                            settings.resolved_marena_model,
                            settings.default_vision_model,
                            settings.default_embedding_model,
                        ]
                    )
                ),
                host=settings.ollama_host,
            )

    if settings.stt_engine == "whisper":
        if in_container:
            raise BootstrapError(
                "whisper.cpp STT is a host-mode feature and is not available "
                "inside the Docker container. Set stt.mode: none (or "
                "VESNAI_STT_ENGINE=none) for the containerized server; the "
                "app's on-device dictation keeps working."
            )
        _ensure_whisper(settings)

    store = voice_store or VoiceRegistrationStore(settings.data_dir)
    if settings.tts_engine == "remote" and store.is_configured():
        reg = store.load()
        if reg is not None and reg.provider == "sidecar":
            _wait_for_http(f"{reg.resolved_url()}/healthz", name="TTS")
    elif settings.tts_engine == "remote":
        log.info("voice_not_configured", detail="TTS disabled until voice service is registered")
    log.info("bootstrap_online_ready")


def _ensure_python_ai_packages(settings: Settings) -> None:
    # Only require packages for components that are actually enabled. The
    # optional in-process TTS engine adds its own extra. mflux/image generation
    # is best-effort and is imported lazily, so it is not required here.
    required: dict[str, str] = {}
    if settings.llm_provider == "ollama":
        required["ollama"] = "ai"
    if settings.resolved_vector_store() == "qdrant":
        required["qdrant_client"] = "ai"
    if settings.tts_engine == "chatterbox":
        required["chatterbox"] = "chatterbox"
    for pkg, extra in required.items():
        try:
            __import__(pkg)
        except ImportError as exc:
            raise BootstrapError(
                f"Missing Python package '{pkg}'. "
                f"Run: cd server && uv sync --extra ai --extra {extra}"
            ) from exc


def _ensure_tts_reference(settings: Settings) -> None:
    if settings.tts_engine != "chatterbox":
        return
    reference = settings.resolved_tts_reference_wav
    if not reference.exists():
        raise BootstrapError(
            f"Chatterbox reference voice not found at {reference}. "
            "Point VESNAI_TTS_REFERENCE_WAV at a mono WAV (5-10 s, single speaker)."
        )


def _ensure_mflux_cli() -> None:
    """Install mflux as an isolated CLI tool so FLUX coexists with Chatterbox.

    mflux pins torch/numpy that clash with chatterbox-tts, so it must live in its
    own environment. ``uv tool install`` gives it a dedicated venv and puts the
    ``mflux-generate`` binary on PATH, which the image provider shells out to.
    """
    if find_mflux_generate() is not None:
        return
    if shutil.which("uv") is None:
        raise BootstrapError(
            "mflux-generate not found and uv is unavailable. Install uv, then run "
            "`uv tool install mflux` for FLUX image generation."
        )
    log.info("bootstrap_install_mflux_cli")
    try:
        install_mflux_tool()
    except RuntimeError as exc:
        raise BootstrapError(
            f"`uv tool install mflux` failed: {exc}. "
            "Ensure the uv tools bin dir is on PATH (uv tool update-shell)."
        ) from exc
    if find_mflux_generate() is None:
        raise BootstrapError(
            "mflux-generate is not on PATH after `uv tool install mflux`. "
            "Add ~/.local/bin to PATH or run `uv tool update-shell` and restart your shell."
        )


def _ensure_docker(settings: Settings) -> None:
    if shutil.which("docker") is None:
        if sys.platform == "darwin" and shutil.which("brew"):
            log.info("bootstrap_install_docker")
            subprocess.run(["brew", "install", "--cask", "docker"], check=False)
            subprocess.run(["open", "-a", "Docker"], check=False)
        raise BootstrapError(
            "Docker is required for Qdrant and SearXNG. Install Docker Desktop, then retry."
        )
    deadline = time.monotonic() + settings.bootstrap_timeout_seconds
    while time.monotonic() < deadline:
        if subprocess.run(["docker", "info"], capture_output=True).returncode == 0:
            return
        if sys.platform == "darwin":
            subprocess.run(["open", "-a", "Docker"], check=False)
        time.sleep(2)
    raise BootstrapError("Docker daemon is not running. Start Docker Desktop and retry.")


def _searxng_secret(settings: Settings) -> str:
    """Per-deploy SearXNG secret, generated once into data_dir (0600)."""
    import os
    import secrets as pysecrets

    path = Path(settings.data_dir) / "searxng_secret"
    if path.exists():
        return path.read_text().strip()
    secret = pysecrets.token_hex(32)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(secret + "\n")
    try:
        os.chmod(path, 0o600)
    except OSError:  # pragma: no cover
        pass
    return secret


def _compose_up(services: list[str], *, settings: Settings | None = None) -> None:
    import os

    if not COMPOSE_FILE.exists():
        raise BootstrapError(f"Missing {COMPOSE_FILE}")
    cmd = [
        "docker",
        "compose",
        "-f",
        str(COMPOSE_FILE),
        "up",
        "-d",
        *services,
    ]
    env = dict(os.environ)
    if "SEARXNG_SECRET" not in env and settings is not None:
        env["SEARXNG_SECRET"] = _searxng_secret(settings)
    log.info("bootstrap_compose_up", services=services)
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if proc.returncode != 0:
        raise BootstrapError(f"docker compose failed: {proc.stderr or proc.stdout}")


def _wait_for_http(url: str, *, name: str, timeout: float | None = None) -> None:
    settings = Settings()
    deadline = time.monotonic() + (timeout or settings.bootstrap_timeout_seconds)
    last_err = ""
    while time.monotonic() < deadline:
        try:
            resp = httpx.get(url, timeout=3.0, follow_redirects=True)
            if resp.status_code < 500:
                log.info("bootstrap_service_ready", service=name, url=url)
                return
            last_err = f"HTTP {resp.status_code}"
        except Exception as exc:  # noqa: BLE001
            last_err = str(exc)
        time.sleep(2)
    raise BootstrapError(f"{name} not ready at {url}: {last_err}")


def _wait_for_searxng(base_url: str) -> None:
    url = f"{base_url.rstrip('/')}/search?q=test&format=json"
    _wait_for_http(url, name="SearXNG")


def _ensure_ollama(settings: Settings, *, in_container: bool = False) -> None:
    host = settings.ollama_host or "http://127.0.0.1:11434"
    try:
        httpx.get(host, timeout=2.0)
        return
    except Exception:
        pass

    if in_container:
        # Never shell out inside a container: the daemon must be another
        # compose service, reachable via VESNAI_OLLAMA_HOST.
        _wait_for_http(host, name="Ollama", timeout=settings.bootstrap_timeout_seconds)
        return

    if shutil.which("ollama") is None:
        if sys.platform == "darwin" and shutil.which("brew"):
            log.info("bootstrap_install_ollama")
            subprocess.run(["brew", "install", "ollama"], check=False)
        if shutil.which("ollama") is None:
            raise BootstrapError("Ollama is not installed. Install from https://ollama.com")

    log.info("bootstrap_ollama_serve")
    subprocess.Popen(
        ["ollama", "serve"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    _wait_for_http(host, name="Ollama", timeout=settings.bootstrap_timeout_seconds)


def _ensure_whisper(settings: Settings) -> None:
    binary = settings.whisper_binary
    if binary and Path(binary).exists():
        return
    if not any(shutil.which(n) for n in ("whisper-cli", "whisper-cpp", "main")):
        if sys.platform == "darwin" and shutil.which("brew"):
            log.info("bootstrap_install_whisper_cpp")
            subprocess.run(["brew", "install", "whisper-cpp", "curl"], check=False)
    if not any(shutil.which(n) for n in ("whisper-cli", "whisper-cpp", "main")):
        raise BootstrapError(
            "whisper.cpp CLI not found. On macOS: brew install whisper-cpp"
        )
    model_path = settings.resolved_whisper_model_path
    if model_path.exists():
        return
    model_path.parent.mkdir(parents=True, exist_ok=True)
    url = (
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
        f"ggml-{settings.stt_model}.bin"
    )
    log.info("bootstrap_whisper_download", model=settings.stt_model, path=str(model_path))
    subprocess.run(["curl", "-fsSL", url, "-o", str(model_path)], check=True)
