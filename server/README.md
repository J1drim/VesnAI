# VesnAI Server

FastAPI server for VesnAI: the OKF Markdown store (source of truth), sync API,
device-pairing auth, background jobs, and AI services (enrichment, chat, web
search, self-tuning) behind mockable provider interfaces.

## Develop

```bash
uv sync                       # or: uv pip install -e ".[dev]"
uv run pytest                 # fast suite (fake providers, no models)
uv run pytest -m live         # opt-in live suite (requires local models/network)
uv run ruff check .
uv run mypy vesnai
```

## Run

```bash
uv run vesnai serve --knowledge-dir ./knowledge
```

See [../docs](../docs) for the OKF profile, API and deployment docs.
