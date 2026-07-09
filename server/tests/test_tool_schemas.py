"""Tool schema tests for Ollama-compatible JSON."""

from __future__ import annotations

from vesnai.ai.tool_schemas import CHAT_TOOLS, UPDATE_MEMORY_TOOL, tool_by_name


def _assert_full_json_schema(params: dict) -> None:
    assert params.get("type") == "object"
    assert isinstance(params.get("properties"), dict)
    assert isinstance(params.get("required"), list)
    assert params.get("additionalProperties") is False
    for spec in params["properties"].values():
        assert "type" in spec
        assert "description" in spec


def test_all_chat_tools_use_full_json_schema():
    names = {t.name for t in CHAT_TOOLS}
    assert "search_chat_history" in names
    assert "update_memory" in names
    assert "read_note" in names
    assert "update_note" in names
    assert "list_due_notes" in names
    assert len(CHAT_TOOLS) >= 23
    for tool in CHAT_TOOLS:
        _assert_full_json_schema(tool.parameters)


def test_update_memory_tool_export_matches_chat_tools():
    found = tool_by_name("update_memory")
    assert found is not None
    assert found.name == UPDATE_MEMORY_TOOL.name
    assert found.parameters == UPDATE_MEMORY_TOOL.parameters


def test_search_chat_history_schema():
    tool = tool_by_name("search_chat_history")
    assert tool is not None
    props = tool.parameters["properties"]
    assert "query" in props
    assert props["query"]["type"] == "string"


def test_web_search_and_note_image_tool_descriptions():
    web = tool_by_name("web_search")
    assert web is not None
    assert "restaurant" in web.description.lower()

    attach = tool_by_name("read_note_attachment")
    assert attach is not None
    assert "generate_image" in attach.description

    gen = tool_by_name("generate_image")
    assert gen is not None
    assert "style_reference_path" in gen.parameters["properties"]
