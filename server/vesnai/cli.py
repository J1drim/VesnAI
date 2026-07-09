"""VesnAI command-line interface."""

from __future__ import annotations

import os
from pathlib import Path

import typer

from vesnai.config import Settings, find_config_file, set_config_file, set_settings

app = typer.Typer(help="VesnAI second-brain server.", no_args_is_help=True)

_FIRST_RUN_MESSAGE = """
Welcome to VesnAI! No configuration was found, so the server starts in
offline demo mode (deterministic fake AI providers — the assistant will not
give real answers).

To configure the real stack:
  1. cp vesnai.example.yaml vesnai.yaml   (in the directory you run from)
  2. Edit vesnai.yaml — pick your LLM (local Ollama or any OpenAI-compatible
     API), models, TTS/STT/image components, and storage paths.
  3. Restart: vesnai serve

Everything can also be set via VESNAI_* environment variables or a .env file;
vesnai.yaml is just the recommended single place. Run `vesnai doctor` to
validate your configuration.
"""


def _has_any_configuration() -> bool:
    """True when a config file, VESNAI_* env vars, or a .env file exist."""
    if find_config_file() is not None:
        return True
    if any(k.startswith("VESNAI_") for k in os.environ):
        return True
    return Path(".env").exists()


def _build_settings(config: Path | None, overrides: dict) -> Settings:
    if config is not None:
        if not config.exists():
            typer.echo(f"Config file not found: {config}", err=True)
            raise typer.Exit(1)
        set_config_file(config)
    # Only explicitly-passed CLI options override the file/env configuration.
    kwargs = {k: v for k, v in overrides.items() if v is not None}
    try:
        return Settings(**kwargs)
    except (ValueError, TypeError) as exc:
        typer.echo(f"Invalid configuration: {exc}", err=True)
        raise typer.Exit(1) from exc


@app.command()
def serve(
    config: Path = typer.Option(
        None,
        "--config",
        "-c",
        help="Path to vesnai.yaml (default: $VESNAI_CONFIG or ./vesnai.yaml).",
    ),
    knowledge_dir: Path = typer.Option(None, help="OKF bundle directory."),
    data_dir: Path = typer.Option(None, help="Derived indexes / state directory."),
    host: str = typer.Option(None),
    port: int = typer.Option(None),
    tls: bool = typer.Option(None, "--tls/--no-tls", help="Serve over HTTPS."),
    cert: Path = typer.Option(None, help="TLS certificate file (PEM)."),
    key: Path = typer.Option(None, help="TLS key file (PEM)."),
    offline: bool = typer.Option(
        None, "--offline/--no-offline", help="Local-only: never call external APIs."
    ),
) -> None:
    """Run the VesnAI server."""
    import uvicorn

    first_run = config is None and not _has_any_configuration()
    settings = _build_settings(
        config,
        {
            "knowledge_dir": knowledge_dir,
            "data_dir": data_dir,
            "host": host,
            "port": port,
            "tls_enabled": tls,
            "tls_cert_file": cert,
            "tls_key_file": key,
            "offline_only": offline,
        },
    )
    set_settings(settings)
    if first_run and settings.offline_only:
        typer.echo(_FIRST_RUN_MESSAGE)

    from vesnai.api.server import create_app
    from vesnai.app_state import AppState
    from vesnai.runtime.bootstrap import BootstrapError

    try:
        state = AppState(settings)
    except BootstrapError as exc:
        typer.echo(f"Online startup failed: {exc}", err=True)
        raise typer.Exit(1) from exc
    application = create_app(state)

    if settings.tls_enabled:
        cert_file, key_file = settings.tls_cert_file, settings.tls_key_file
        # Fail closed: never silently fall back to plain HTTP when TLS is on.
        if not cert_file or not key_file:
            typer.echo(
                "TLS is enabled but no certificate/key is configured.\n"
                "  - Generate a trusted dev cert:  ./scripts/vesnai.sh setup-https\n"
                "  - Then pass --cert/--key (or set network.tls in vesnai.yaml).\n"
                "  - For localhost-only testing you can opt out with --no-tls.",
                err=True,
            )
            raise typer.Exit(1)
        if not Path(cert_file).exists() or not Path(key_file).exists():
            typer.echo(
                f"TLS cert/key not found: {cert_file} / {key_file}", err=True
            )
            raise typer.Exit(1)
        uvicorn.run(
            application,
            host=settings.host,
            port=settings.port,
            ssl_certfile=str(cert_file),
            ssl_keyfile=str(key_file),
        )
        return
    uvicorn.run(application, host=settings.host, port=settings.port)


@app.command()
def pair(
    config: Path = typer.Option(
        None,
        "--config",
        "-c",
        help="Path to vesnai.yaml (default: $VESNAI_CONFIG or ./vesnai.yaml).",
    ),
    data_dir: Path = typer.Option(None, help="Server data directory (holds the bootstrap secret)."),
    url: str = typer.Option(
        None, help="Server base URL (default: derived from the configuration)."
    ),
) -> None:
    """Mint a pairing code on the running server (host-only bootstrap secret)."""
    import httpx

    from vesnai.auth import BOOTSTRAP_SECRET_FILENAME

    settings = _build_settings(config, {"data_dir": data_dir})
    secret_path = Path(settings.data_dir) / BOOTSTRAP_SECRET_FILENAME
    if not secret_path.exists():
        typer.echo(
            f"Bootstrap secret not found at {secret_path}.\n"
            "Start the server once (`vesnai serve`) to generate it, and run this "
            "command on the server host with the same --data-dir/config.",
            err=True,
        )
        raise typer.Exit(1)
    secret = secret_path.read_text().strip()

    scheme = "https" if settings.tls_enabled else "http"
    base = url or f"{scheme}://127.0.0.1:{settings.port}"
    try:
        # verify=False is safe here: we connect to the local server over
        # loopback and authenticate it with the shared bootstrap secret.
        resp = httpx.post(
            f"{base.rstrip('/')}/v1/auth/pair/code",
            headers={"X-VesnAI-Bootstrap": secret},
            timeout=10.0,
            verify=False,
        )
    except httpx.HTTPError as exc:
        typer.echo(
            f"Could not reach the server at {base} ({exc}).\n"
            "Is `vesnai serve` running? Pass --url if it listens elsewhere.",
            err=True,
        )
        raise typer.Exit(1) from exc
    if resp.status_code != 200:
        typer.echo(f"Server refused ({resp.status_code}): {resp.text}", err=True)
        raise typer.Exit(1)
    body = resp.json()
    typer.echo(f"Pairing code (valid {body['expires_in'] // 60} min): {body['code']}")
    typer.echo(f"Server URL for the app: {body['url']}")


@app.command()
def doctor(
    config: Path = typer.Option(
        None,
        "--config",
        "-c",
        help="Path to vesnai.yaml (default: $VESNAI_CONFIG or ./vesnai.yaml).",
    ),
    knowledge_dir: Path = typer.Option(None, help="OKF bundle directory (overrides config)."),
) -> None:
    """Validate the configuration and check the bundle for OKF issues."""
    from vesnai.okf import check_bundle
    from vesnai.okf.bundle import BundleStore

    # --- configuration ---------------------------------------------------- #
    settings = _build_settings(config, {"knowledge_dir": knowledge_dir})
    config_path = config or find_config_file()
    if config_path is not None:
        typer.echo(f"Config file: {config_path}")
    else:
        typer.echo("Config file: none (using env vars / defaults)")

    problems: list[str] = []
    if settings.llm_provider not in ("ollama", "openai_compatible"):
        problems.append(f"llm.provider {settings.llm_provider!r} is not ollama|openai_compatible")
    if settings.llm_provider == "openai_compatible" and not settings.llm_base_url:
        problems.append("llm.provider is openai_compatible but llm.base_url is missing")
    if settings.tts_engine not in ("remote", "chatterbox", "none"):
        problems.append(
            f"tts engine {settings.tts_engine!r} is not remote|chatterbox|none "
            "(note: the GPL 'kokoro' engine was removed)"
        )
    if settings.stt_engine not in ("whisper", "none"):
        problems.append(f"stt engine {settings.stt_engine!r} is not whisper|none")
    if settings.image_engine not in ("flux", "none"):
        problems.append(f"image engine {settings.image_engine!r} is not flux|none")
    if settings.vector_store not in ("auto", "qdrant", "in_memory"):
        problems.append(f"vector_store {settings.vector_store!r} is not auto|qdrant|in_memory")
    if settings.search_engine not in ("searxng", "none"):
        problems.append(f"search engine {settings.search_engine!r} is not searxng|none")

    typer.echo(
        f"Mode: {'offline (fake AI)' if settings.offline_only else 'online'} | "
        f"llm={settings.llm_provider} chat={settings.default_chat_model} "
        f"reasoning={settings.default_reasoning_model} marena={settings.resolved_marena_model} | "
        f"vector={settings.resolved_vector_store()} search={settings.search_engine} "
        f"stt={settings.stt_engine} image={settings.image_engine} tts={settings.tts_engine}"
    )
    if not settings.offline_only and settings.llm_provider == "openai_compatible":
        typer.echo(
            "NOTE: openai_compatible sends note content to the configured endpoint."
        )
    for p in problems:
        typer.echo(f"[error] config: {p}")

    # --- bundle ----------------------------------------------------------- #
    store = BundleStore(settings.knowledge_dir)
    issues = check_bundle(store.list_concepts())
    for issue in issues:
        typer.echo(f"[{issue.severity.value}] {issue.path}: {issue.message}")
    errors = [i for i in issues if i.severity.value == "error"]
    if not issues and not problems:
        typer.echo("OK: configuration valid, no conformance issues found.")
    raise typer.Exit(1 if (errors or problems) else 0)


if __name__ == "__main__":
    app()
