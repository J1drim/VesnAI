# VesnAI server image. The default offline mode needs no models, so this image
# boots and serves the full API (with deterministic providers) out of the box.
FROM python:3.12-slim AS base

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VESNAI_KNOWLEDGE_DIR=/data/knowledge \
    VESNAI_DATA_DIR=/data/state

RUN apt-get update && apt-get install -y --no-install-recommends git curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pyproject.toml README.md uv.lock ./
COPY vesnai ./vesnai

RUN pip install --upgrade pip uv \
    && uv sync --frozen --no-dev \
    && uv pip install --system .

VOLUME ["/data"]
EXPOSE 8443

# Bind loopback by default; map ports in compose and mount TLS certs for LAN use.
# Pass --cert/--key for HTTPS, or --host 0.0.0.0 --no-tls only on trusted LANs.
ENTRYPOINT ["vesnai"]
CMD ["serve", "--host", "127.0.0.1", "--port", "8443", \
     "--knowledge-dir", "/data/knowledge", "--data-dir", "/data/state"]
