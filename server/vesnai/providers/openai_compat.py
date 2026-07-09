"""OpenAI-compatible LLM providers (chat, vision, embeddings).

Works against any endpoint implementing ``/v1/chat/completions`` and
``/v1/embeddings``: OpenAI, OpenRouter, vLLM, llama.cpp server, LM Studio, …
Implements the same provider protocols as the Ollama backends, with the
API-contract differences handled here:

- Tool calls carry provider-assigned ``id``s; assistant messages echo their
  ``tool_calls`` and tool results echo ``tool_call_id`` (strict endpoints
  reject the conversation otherwise).
- Structured output tries ``response_format: json_schema`` first and falls
  back to JSON mode with the schema embedded in the prompt (vLLM/llama.cpp/
  LM Studio support ``json_schema`` inconsistently).
- ``think`` has no portable equivalent; it is mapped to ``reasoning_effort``
  when the endpoint accepts it and silently dropped (with one log line) when
  it does not.
- Vision uses ``image_url`` content parts with data URIs (Ollama takes raw
  base64 ``images`` instead).
"""

from __future__ import annotations

import base64
import json
from typing import Any

import httpx

from vesnai.observability import get_logger
from vesnai.providers.base import ChatMessage, ToolCall, ToolSpec

log = get_logger("vesnai.providers.openai_compat")

_DEFAULT_TIMEOUT = 300.0


class OpenAICompatError(RuntimeError):
    """Raised when the endpoint returns an unusable response."""


def _messages_to_openai(messages: list[ChatMessage]) -> list[dict]:
    out: list[dict] = []
    for m in messages:
        entry: dict[str, Any] = {"role": m.role}
        if m.images:
            # Multimodal user content: text + data-URI image parts.
            parts: list[dict] = []
            if m.content:
                parts.append({"type": "text", "text": m.content})
            for img in m.images:
                b64 = base64.b64encode(img).decode()
                parts.append(
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/png;base64,{b64}"},
                    }
                )
            entry["content"] = parts
        else:
            entry["content"] = m.content or ""
        if m.role == "assistant" and m.tool_calls:
            entry["tool_calls"] = [
                {
                    "id": c.id or f"call_{i}",
                    "type": "function",
                    "function": {
                        "name": c.name,
                        "arguments": json.dumps(c.arguments),
                    },
                }
                for i, c in enumerate(m.tool_calls)
            ]
        if m.role == "tool":
            if m.tool_call_id:
                entry["tool_call_id"] = m.tool_call_id
            if m.name:
                entry["name"] = m.name
        out.append(entry)
    return out


def _tool_parameters(spec: ToolSpec) -> dict:
    params = spec.parameters
    if params.get("type") == "object":
        return params
    return {
        "type": "object",
        "properties": {k: {"type": v} for k, v in params.items()},
    }


class _OpenAIClient:
    """Shared HTTP plumbing for the chat/vision/embedding providers."""

    def __init__(
        self,
        base_url: str,
        api_key: str | None,
        *,
        timeout: float | None = None,
        client: httpx.Client | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        headers = {"Content-Type": "application/json"}
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
        self._client = client or httpx.Client(
            timeout=timeout or _DEFAULT_TIMEOUT, headers=headers
        )

    def post(self, path: str, payload: dict) -> dict:
        resp = self._client.post(f"{self.base_url}{path}", json=payload)
        if resp.status_code >= 400:
            raise OpenAICompatError(
                f"{path} returned HTTP {resp.status_code}: {resp.text[:500]}"
            )
        return resp.json()

    def try_post(self, path: str, payload: dict) -> tuple[dict | None, str]:
        """POST returning (json, "") on success or (None, error_text) on 4xx."""
        resp = self._client.post(f"{self.base_url}{path}", json=payload)
        if resp.status_code >= 400:
            return None, f"HTTP {resp.status_code}: {resp.text[:500]}"
        return resp.json(), ""


class OpenAICompatAIProvider:
    """AIProvider backed by an OpenAI-compatible chat-completions endpoint."""

    def __init__(
        self,
        model: str,
        base_url: str,
        api_key: str | None = None,
        *,
        think: bool = False,
        reasoning_effort: str = "medium",
        timeout: float | None = None,
        client: httpx.Client | None = None,
    ) -> None:
        self.model = model
        self.default_think = think
        self.reasoning_effort = reasoning_effort
        self._http = _OpenAIClient(base_url, api_key, timeout=timeout, client=client)
        # Feature probes resolved lazily on first use (None = unknown).
        self._supports_reasoning_effort: bool | None = None
        self._supports_json_schema: bool | None = None

    # ------------------------------------------------------------------ chat
    def chat(
        self,
        messages: list[ChatMessage],
        tools: list[ToolSpec] | None = None,
        *,
        temperature: float = 0.2,
        think: bool = False,
    ) -> ChatMessage:
        payload: dict[str, Any] = {
            "model": self.model,
            "messages": _messages_to_openai(messages),
            "temperature": temperature,
        }
        if tools:
            payload["tools"] = [
                {
                    "type": "function",
                    "function": {
                        "name": t.name,
                        "description": t.description,
                        "parameters": _tool_parameters(t),
                    },
                }
                for t in tools
            ]
        data = self._post_with_optional_reasoning(payload, think=think)
        msg = _first_message(data)
        calls = [
            ToolCall(
                name=c.get("function", {}).get("name", ""),
                arguments=_as_dict(c.get("function", {}).get("arguments", {})),
                id=c.get("id"),
            )
            for c in msg.get("tool_calls") or []
        ]
        return ChatMessage(
            role="assistant", content=msg.get("content") or "", tool_calls=calls
        )

    def complete(
        self, prompt: str, *, temperature: float = 0.2, think: bool = False
    ) -> str:
        reply = self.chat(
            [ChatMessage(role="user", content=prompt)],
            temperature=temperature,
            think=think,
        )
        return reply.content.strip()

    def complete_structured(
        self,
        prompt: str,
        schema: dict,
        *,
        temperature: float = 0.2,
        think: bool = False,
    ) -> str:
        base_payload: dict[str, Any] = {
            "model": self.model,
            "temperature": temperature,
        }
        # Preferred: native json_schema response format.
        if self._supports_json_schema is not False:
            payload = {
                **base_payload,
                "messages": _messages_to_openai(
                    [ChatMessage(role="user", content=prompt)]
                ),
                "response_format": {
                    "type": "json_schema",
                    "json_schema": {
                        "name": "structured_output",
                        "schema": schema,
                        "strict": False,
                    },
                },
            }
            data, err = self._http.try_post("/chat/completions", payload)
            if data is not None:
                self._supports_json_schema = True
                return (_first_message(data).get("content") or "").strip()
            if self._supports_json_schema is None:
                log.info(
                    "openai_compat_json_schema_unsupported",
                    detail=err,
                    fallback="json mode + prompt-embedded schema",
                )
            self._supports_json_schema = False

        # Fallback: JSON mode with the schema embedded in the prompt, retried
        # once if the reply is not valid JSON.
        schema_prompt = (
            f"{prompt}\n\nRespond with a single JSON object matching this JSON "
            f"schema exactly (no prose, no code fences):\n{json.dumps(schema)}"
        )
        for attempt in range(2):
            payload = {
                **base_payload,
                "messages": _messages_to_openai(
                    [ChatMessage(role="user", content=schema_prompt)]
                ),
                "response_format": {"type": "json_object"},
            }
            data, err = self._http.try_post("/chat/completions", payload)
            if data is None:
                # Some servers lack json_object mode too; final try is plain.
                payload.pop("response_format")
                data = self._http.post("/chat/completions", payload)
            content = (_first_message(data).get("content") or "").strip()
            cleaned = _strip_code_fences(content)
            try:
                json.loads(cleaned)
                return cleaned
            except ValueError as exc:
                if attempt == 0:
                    log.info("openai_compat_structured_retry", reply_prefix=content[:120])
                    continue
                raise OpenAICompatError(
                    f"endpoint did not return valid JSON for structured output: {content[:200]}"
                ) from exc
        raise OpenAICompatError("unreachable")  # pragma: no cover

    def _post_with_optional_reasoning(self, payload: dict, *, think: bool) -> dict:
        wants_reasoning = (think or self.default_think) and self.reasoning_effort
        if wants_reasoning and self._supports_reasoning_effort is not False:
            probe = {**payload, "reasoning_effort": self.reasoning_effort}
            data, err = self._http.try_post("/chat/completions", probe)
            if data is not None:
                self._supports_reasoning_effort = True
                return data
            if self._supports_reasoning_effort is None:
                log.info(
                    "openai_compat_reasoning_effort_unsupported",
                    detail=err,
                    action="thinking flag will be ignored for this endpoint",
                )
            self._supports_reasoning_effort = False
        return self._http.post("/chat/completions", payload)


class OpenAICompatVisionProvider:
    """VisionProvider via image_url content parts (data URIs)."""

    def __init__(
        self,
        model: str,
        base_url: str,
        api_key: str | None = None,
        *,
        timeout: float | None = None,
        client: httpx.Client | None = None,
    ) -> None:
        self.model = model
        self._http = _OpenAIClient(base_url, api_key, timeout=timeout, client=client)

    def caption(self, image: bytes, prompt: str) -> str:
        message = ChatMessage(role="user", content=prompt, images=[image])
        data = self._http.post(
            "/chat/completions",
            {"model": self.model, "messages": _messages_to_openai([message])},
        )
        return (_first_message(data).get("content") or "").strip()


class OpenAICompatEmbeddingProvider:
    def __init__(
        self,
        model: str,
        base_url: str,
        api_key: str | None = None,
        *,
        dim: int = 1024,
        timeout: float | None = None,
        client: httpx.Client | None = None,
    ) -> None:
        self.model = model
        self._dim = dim
        self._http = _OpenAIClient(base_url, api_key, timeout=timeout, client=client)

    @property
    def dim(self) -> int:
        return self._dim

    def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        data = self._http.post(
            "/embeddings", {"model": self.model, "input": list(texts)}
        )
        rows = sorted(data.get("data", []), key=lambda r: r.get("index", 0))
        vectors = [list(r["embedding"]) for r in rows]
        if len(vectors) != len(texts):
            raise OpenAICompatError(
                f"embeddings endpoint returned {len(vectors)} vectors for {len(texts)} inputs"
            )
        return vectors


def _first_message(data: dict) -> dict:
    choices = data.get("choices") or []
    if not choices:
        raise OpenAICompatError(f"no choices in response: {json.dumps(data)[:300]}")
    return choices[0].get("message") or {}


def _as_dict(value: Any) -> dict:
    if isinstance(value, dict):
        return value
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return {}


def _strip_code_fences(text: str) -> str:
    stripped = text.strip()
    if stripped.startswith("```"):
        first_newline = stripped.find("\n")
        if first_newline != -1:
            stripped = stripped[first_newline + 1 :]
        if stripped.rstrip().endswith("```"):
            stripped = stripped.rstrip()[:-3]
    return stripped.strip()
