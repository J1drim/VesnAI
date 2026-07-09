"""Prompt contract tests for chat tool discipline."""

from __future__ import annotations

from vesnai.ai.chat import (
    MEMORY_MUST_RULES,
    PLAYBOOK_MUST_RULES,
    TOOL_RECIPES,
    TOOLS,
    build_system_content,
)
from vesnai.ai.tool_guardrails import TOOL_USE_ENFORCEMENT


def test_build_system_content_includes_memory_and_enforcement():
    content = build_system_content(rag="(none)", memory_block="", language="en")
    assert "update_memory" in content or "update long-term memory" in content
    assert "zapamiętaj" in MEMORY_MUST_RULES
    assert TOOL_USE_ENFORCEMENT in content
    assert MEMORY_MUST_RULES.split("\n")[0] in content or "Memory vs notes" in content
    assert "create_playbook" in PLAYBOOK_MUST_RULES


def test_build_system_content_includes_tool_recipes_and_never_refuse():
    content = build_system_content(rag="(none)", memory_block="", language="pl")
    assert TOOL_RECIPES in content or "Tool recipes:" in content
    assert "web_search" in content
    assert "Never refuse" in content or "Never refuse local" in content
    assert "read_note_attachment" in content


def test_tools_include_memory_and_playbooks():
    names = {t.name for t in TOOLS}
    assert "update_memory" in names
    assert "create_playbook" in names
    assert "update_playbook" in names


def test_web_search_tool_mentions_restaurants():
    tool = next(t for t in TOOLS if t.name == "web_search")
    assert "restaurant" in tool.description.lower()


def test_read_note_attachment_mentions_style_workflow():
    tool = next(t for t in TOOLS if t.name == "read_note_attachment")
    assert "style" in tool.description.lower()
    assert "generate_image" in tool.description
