# VesnAI server image. The default offline mode needs no models, so this image
# boots and serves the full API (with deterministic providers) out of the box.
FROM python:3.14-slim@sha256:cad9a2c871761c413caa6fdd6441c783451e740a48aaeba60ae62a8b53525ef6 AS base
COPY --from=ghcr.io/astral-sh/uv:0.11.16@sha256:440fd6477af86a2f1b38080c539f1672cd22acb1b1a47e321dba5158ab08864d /uv /uvx /bin/

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VESNAI_KNOWLEDGE_DIR=/data/knowledge \
    VESNAI_DATA_DIR=/data/state \
    PATH="/app/.venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends git curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pyproject.toml README.md uv.lock ./
COPY vesnai ./vesnai

# Run the committed resolution, not a second unpinned system installation.
RUN uv sync --locked --no-dev --no-editable

VOLUME ["/data"]
EXPOSE 8443

# Bind loopback by default; map ports in compose and mount TLS certs for LAN use.
# Pass --cert/--key for HTTPS, or --host 0.0.0.0 --no-tls only on trusted LANs.
ENTRYPOINT ["vesnai"]
CMD ["serve", "--host", "127.0.0.1", "--port", "8443", \
     "--knowledge-dir", "/data/knowledge", "--data-dir", "/data/state"]
