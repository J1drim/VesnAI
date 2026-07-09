"""Ollama-backed local LLM + embedding providers (optional integration).

Requires the ``ollama`` package and a running Ollama daemon. Used when offline
mode is disabled and the integration is available. Implements the same
:class:`AIProvider` / :class:`EmbeddingProvider` protocols as the fakes.
"""

from __future__ import annotations

import json

from vesnai.providers.base import ChatMessage, ToolCall, ToolSpec


class OllamaAIProvider:
    def __init__(
        self,
        model: str = "qwen3.6",
        host: str | None = None,
        *,
        think: bool = False,
        keep_alive: str = "30m",
        timeout: float | None = None,
    ) -> None:
        import ollama  # noqa: F401

        self.model = model
        self.default_think = think
        self.keep_alive = keep_alive
        client_kwargs: dict = {}
        if timeout is not None:
            client_kwargs["timeout"] = timeout
        self._client = (
            ollama.Client(host=host, **client_kwargs)
            if host
            else ollama.Client(**client_kwargs)
        )

    def _to_ollama(self, messages: list[ChatMessage]) -> list[dict]:
        out = []
        for m in messages:
            entry: dict = {"role": m.role, "content": m.content}
            if m.name:
                entry["name"] = m.name
            if m.role == "assistant" and m.tool_calls:
                # Echo the calls so the transcript stays well-formed; Ollama
                # tolerates (and newer versions expect) this shape.
                entry["tool_calls"] = [
                    {"function": {"name": c.name, "arguments": c.arguments}}
                    for c in m.tool_calls
                ]
            if m.images:
                import base64

                entry["images"] = [base64.b64encode(img).decode() for img in m.images]
            out.append(entry)
        return out

    def _tool_parameters(self, spec: ToolSpec) -> dict:
        params = spec.parameters
        if params.get("type") == "object":
            return params
        return {
            "type": "object",
            "properties": {k: {"type": v} for k, v in params.items()},
        }

    def chat(
        self,
        messages: list[ChatMessage],
        tools: list[ToolSpec] | None = None,
        *,
        temperature: float = 0.2,
        think: bool = False,
    ) -> ChatMessage:
        tool_payload = (
            [
                {
                    "type": "function",
                    "function": {
                        "name": t.name,
                        "description": t.description,
                        "parameters": self._tool_parameters(t),
                    },
                }
                for t in tools
            ]
            if tools
            else None
        )
        resp = self._client.chat(
            model=self.model,
            messages=self._to_ollama(messages),
            tools=tool_payload,
            think=think or self.default_think,
            keep_alive=self.keep_alive,
            options={"temperature": temperature},
        )
        msg = resp["message"]
        calls = [
            ToolCall(
                name=c["function"]["name"],
                arguments=_as_dict(c["function"].get("arguments", {})),
            )
            for c in msg.get("tool_calls", []) or []
        ]
        return ChatMessage(role="assistant", content=msg.get("content", ""), tool_calls=calls)

    def complete(self, prompt: str, *, temperature: float = 0.2, think: bool = False) -> str:
        resp = self._client.generate(
            model=self.model,
            prompt=prompt,
            think=think or self.default_think,
            keep_alive=self.keep_alive,
            options={"temperature": temperature},
        )
        return resp.get("response", "").strip()

    def complete_structured(
        self,
        prompt: str,
        schema: dict,
        *,
        temperature: float = 0.2,
        think: bool = False,
    ) -> str:
        resp = self._client.generate(
            model=self.model,
            prompt=prompt,
            format=schema,
            think=think or self.default_think,
            keep_alive=self.keep_alive,
            options={"temperature": temperature},
        )
        return resp.get("response", "").strip()


class OllamaVisionProvider:
    """Multimodal captioner via Ollama (e.g. Qwen3.6 with an mmproj projector)."""

    def __init__(
        self, model: str = "qwen3.6", host: str | None = None, *, keep_alive: str = "30m",
        timeout: float | None = None,
    ) -> None:
        import ollama  # noqa: F401

        self.model = model
        self.keep_alive = keep_alive
        client_kwargs: dict = {}
        if timeout is not None:
            client_kwargs["timeout"] = timeout
        self._client = (
            ollama.Client(host=host, **client_kwargs)
            if host
            else ollama.Client(**client_kwargs)
        )

    def caption(self, image: bytes, prompt: str) -> str:
        import base64

        resp = self._client.generate(
            model=self.model,
            prompt=prompt,
            images=[base64.b64encode(image).decode()],
            keep_alive=self.keep_alive,
        )
        return resp.get("response", "").strip()


class OllamaEmbeddingProvider:
    def __init__(self, model: str = "bge-m3", dim: int = 1024, host: str | None = None,
                 timeout: float | None = None):
        import ollama  # noqa: F401

        self.model = model
        self._dim = dim
        client_kwargs: dict = {}
        if timeout is not None:
            client_kwargs["timeout"] = timeout
        self._client = (
            ollama.Client(host=host, **client_kwargs)
            if host
            else ollama.Client(**client_kwargs)
        )

    @property
    def dim(self) -> int:
        return self._dim

    def embed(self, texts: list[str]) -> list[list[float]]:
        out = []
        for t in texts:
            out.append(self._embed_one(t))
        return out

    def _embed_one(self, text: str) -> list[float]:
        from ollama import ResponseError

        prompt = (text or "").strip()
        limits = (6000, 3000, 1500)
        last_exc: Exception | None = None
        for limit in limits:
            chunk = prompt if len(prompt) <= limit else prompt[: limit - 20].rstrip() + "…"
            try:
                resp = self._client.embeddings(model=self.model, prompt=chunk)
                return list(resp["embedding"])
            except ResponseError as exc:
                last_exc = exc
                if "context length" not in str(exc).lower():
                    raise
            except Exception as exc:
                last_exc = exc
                msg = str(exc).lower()
                if "context length" not in msg and "too long" not in msg:
                    raise
        assert last_exc is not None
        raise last_exc


def _as_dict(value) -> dict:
    if isinstance(value, dict):
        return value
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return {}


def model_is_installed(requested: str, installed: set[str]) -> bool:
    """Return True if ``requested`` is already present in the local Ollama library.

    ``qwen3.6`` matches ``qwen3.6:latest``; ``qwen3.5:122b-a10b`` requires that tag.
    """
    if requested in installed:
        return True
    req_base = requested.split(":", 1)[0]
    for name in installed:
        if name == requested:
            return True
        if name.split(":", 1)[0] == req_base and ":" not in requested:
            return True
    return False


def ensure_models(models: list[str], *, host: str | None = None) -> None:
    """Pull any Ollama models that are not already on disk (first-run online setup)."""
    import ollama

    from vesnai.observability import get_logger

    log = get_logger("vesnai.providers.ollama")
    client = ollama.Client(host=host) if host else ollama.Client()
    installed = {m.model for m in client.list().models if m.model}
    missing = [m for m in dict.fromkeys(models) if not model_is_installed(m, installed)]
    if not missing:
        log.info("ollama_models_ready", models=list(dict.fromkeys(models)))
        return

    for model in missing:
        log.info("ollama_pull_start", model=model)
        for progress in client.pull(model, stream=True):
            status = progress.status or ""
            completed = progress.completed or 0
            total = progress.total or 0
            if total > 0:
                pct = int(100 * completed / total)
                log.info(
                    "ollama_pull_progress",
                    model=model,
                    status=status,
                    percent=pct,
                    completed=completed,
                    total=total,
                )
            elif status:
                log.info("ollama_pull_progress", model=model, status=status)
        log.info("ollama_pull_done", model=model)
