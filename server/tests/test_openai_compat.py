"""OpenAI-compatible provider: message mapping, tool-call ids, fallbacks."""

from __future__ import annotations

import json

import httpx
import pytest

from vesnai.providers.base import ChatMessage, ToolCall, ToolSpec
from vesnai.providers.openai_compat import (
    OpenAICompatAIProvider,
    OpenAICompatEmbeddingProvider,
    OpenAICompatVisionProvider,
    _messages_to_openai,
)

BASE = "https://llm.example/v1"


def _provider(handler, **kwargs) -> OpenAICompatAIProvider:
    client = httpx.Client(
        transport=httpx.MockTransport(handler), headers={"Authorization": "Bearer k"}
    )
    return OpenAICompatAIProvider("test-model", BASE, "k", client=client, **kwargs)


def _chat_response(message: dict) -> httpx.Response:
    return httpx.Response(200, json={"choices": [{"message": message}]})


def test_chat_parses_tool_calls_with_ids():
    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        assert body["model"] == "test-model"
        assert body["tools"][0]["function"]["name"] == "create_note"
        return _chat_response(
            {
                "role": "assistant",
                "content": "",
                "tool_calls": [
                    {
                        "id": "call_abc",
                        "type": "function",
                        "function": {
                            "name": "create_note",
                            "arguments": '{"title": "T"}',
                        },
                    }
                ],
            }
        )

    reply = _provider(handler).chat(
        [ChatMessage(role="user", content="hi")],
        tools=[ToolSpec(name="create_note", description="", parameters={"type": "object"})],
    )
    assert reply.tool_calls[0].id == "call_abc"
    assert reply.tool_calls[0].name == "create_note"
    assert reply.tool_calls[0].arguments == {"title": "T"}


def test_assistant_tool_calls_and_tool_results_are_echoed():
    messages = [
        ChatMessage(
            role="assistant",
            content="",
            tool_calls=[ToolCall(name="f", arguments={"a": 1}, id="call_1")],
        ),
        ChatMessage(role="tool", name="f", content='{"ok": true}', tool_call_id="call_1"),
    ]
    mapped = _messages_to_openai(messages)
    assert mapped[0]["tool_calls"][0]["id"] == "call_1"
    assert json.loads(mapped[0]["tool_calls"][0]["function"]["arguments"]) == {"a": 1}
    assert mapped[1]["tool_call_id"] == "call_1"
    assert mapped[1]["role"] == "tool"


def test_structured_output_falls_back_to_json_mode():
    calls: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        calls.append(body)
        fmt = body.get("response_format", {})
        if fmt.get("type") == "json_schema":
            return httpx.Response(400, json={"error": "response_format not supported"})
        return _chat_response({"role": "assistant", "content": '{"answer": 42}'})

    out = _provider(handler).complete_structured("q", {"type": "object"})
    assert json.loads(out) == {"answer": 42}
    # First attempt used json_schema, the fallback used json_object.
    assert calls[0]["response_format"]["type"] == "json_schema"
    assert calls[1]["response_format"]["type"] == "json_object"


def test_thinking_falls_back_when_reasoning_effort_rejected():
    seen: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        seen.append(body)
        if "reasoning_effort" in body:
            return httpx.Response(400, json={"error": "unknown parameter"})
        return _chat_response({"role": "assistant", "content": "ok"})

    provider = _provider(handler, think=True)
    assert provider.chat([ChatMessage(role="user", content="hi")]).content == "ok"
    assert "reasoning_effort" in seen[0]
    assert "reasoning_effort" not in seen[1]
    # The probe result is cached: no retry storm on the next call.
    provider.chat([ChatMessage(role="user", content="again")])
    assert "reasoning_effort" not in seen[2]


def test_vision_uses_image_url_data_uri():
    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        parts = body["messages"][0]["content"]
        assert parts[0] == {"type": "text", "text": "describe"}
        assert parts[1]["image_url"]["url"].startswith("data:image/png;base64,")
        return _chat_response({"role": "assistant", "content": "a cat"})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = OpenAICompatVisionProvider("vis", BASE, "k", client=client)
    assert provider.caption(b"\x89PNG...", "describe") == "a cat"


def test_embeddings_roundtrip_and_count_check():
    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        assert body["input"] == ["a", "b"]
        return httpx.Response(
            200,
            json={
                "data": [
                    {"index": 1, "embedding": [0.3, 0.4]},
                    {"index": 0, "embedding": [0.1, 0.2]},
                ]
            },
        )

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = OpenAICompatEmbeddingProvider("emb", BASE, "k", dim=2, client=client)
    vectors = provider.embed(["a", "b"])
    assert vectors == [[0.1, 0.2], [0.3, 0.4]]  # sorted by index
    assert provider.dim == 2


def test_chat_error_surfaces_status_and_body():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": "bad key"})

    from vesnai.providers.openai_compat import OpenAICompatError

    with pytest.raises(OpenAICompatError, match="401"):
        _provider(handler).chat([ChatMessage(role="user", content="hi")])
