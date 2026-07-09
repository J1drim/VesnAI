"""Full JSON Schema definitions for chat tools (Ollama / OpenAI-compatible)."""

from __future__ import annotations

from vesnai.providers.base import ToolSpec


def _obj(*, properties: dict, required: list[str]) -> dict:
    return {
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": False,
    }


def tool_by_name(name: str) -> ToolSpec | None:
    for spec in CHAT_TOOLS:
        if spec.name == name:
            return spec
    return None


UPDATE_MEMORY_TOOL = ToolSpec(
    name="update_memory",
    description=(
        "Save a durable fact, user preference, or active project focus to long-term memory "
        "(memory.md / user.md / projects.md). Use when the user asks to remember something "
        "or states a stable preference. Do NOT use for note-sized content — use create_note."
    ),
    parameters=_obj(
        properties={
            "action": {
                "type": "string",
                "description": "add, replace, or remove",
            },
            "target": {
                "type": "string",
                "description": "memory, user, or projects",
            },
            "entry": {
                "type": "string",
                "description": "Bullet text without leading dash",
            },
            "replace_match": {
                "type": "string",
                "description": "Optional substring of existing bullet to replace/remove",
            },
        },
        required=["action", "target", "entry"],
    ),
)


CHAT_TOOLS: list[ToolSpec] = [
    ToolSpec(
        name="search_notes",
        description=(
            "Semantic search over the user's notes. Returns matching note paths and titles. "
            "Use when the user asks about their saved notes, past ideas, or knowledge base content. "
            "Follow with read_note to load full content."
        ),
        parameters=_obj(
            properties={
                "query": {"type": "string", "description": "Search query in natural language"},
                "top_k": {
                    "type": "integer",
                    "description": "Maximum number of results (default 4)",
                },
            },
            required=["query"],
        ),
    ),
    ToolSpec(
        name="read_note",
        description=(
            "Read a note's title, body, tags, attachments, and links by path. "
            "Use after search_notes when the user asks about a specific note or its content."
        ),
        parameters=_obj(
            properties={
                "path": {"type": "string", "description": "Note relative path from search_notes"},
            },
            required=["path"],
        ),
    ),
    ToolSpec(
        name="read_note_attachment",
        description=(
            "Read text or describe an image/PDF attachment from a saved note. "
            "REQUIRED when the user references a photo, image, or file in a note you have "
            "not loaded — never claim you cannot see note images without calling this first. "
            "Workflow: search_notes → read_note (see attachment paths) → read_note_attachment. "
            "Use for style references before generate_image(style_reference_path=...)."
        ),
        parameters=_obj(
            properties={
                "note_path": {
                    "type": "string",
                    "description": "Note path; if attachment_path omitted, uses first image",
                },
                "attachment_path": {
                    "type": "string",
                    "description": "Bundle attachment path e.g. attachments/photo.png",
                },
            },
            required=["note_path"],
        ),
    ),
    ToolSpec(
        name="list_notes",
        description=(
            "List the user's notes with optional filters. "
            "Use for browsing by type, tag, or origin (not semantic search)."
        ),
        parameters=_obj(
            properties={
                "type": {"type": "string", "description": "Filter by note type e.g. Task, Idea"},
                "tag": {"type": "string", "description": "Filter by tag"},
                "origin": {
                    "type": "string",
                    "description": "Filter by origin: user or generated",
                },
                "limit": {"type": "integer", "description": "Max results (default 20)"},
            },
            required=[],
        ),
    ),
    ToolSpec(
        name="get_note_links",
        description="List notes linked from a given note (knowledge graph neighbors).",
        parameters=_obj(
            properties={
                "path": {"type": "string", "description": "Source note path"},
            },
            required=["path"],
        ),
    ),
    ToolSpec(
        name="update_note",
        description=(
            "Update an existing note's title, body, tags, or type. "
            "Use when the user asks to edit, append to, or reclassify a saved note."
        ),
        parameters=_obj(
            properties={
                "path": {"type": "string", "description": "Note relative path"},
                "title": {"type": "string", "description": "New title"},
                "body": {"type": "string", "description": "New body (replaces entire body)"},
                "tags": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Replace tags list",
                },
                "type": {
                    "type": "string",
                    "description": "New note type e.g. Note, Idea, Task, Photo",
                },
            },
            required=["path"],
        ),
    ),
    ToolSpec(
        name="delete_note",
        description="Delete a note by path. Use only when the user explicitly asks to delete.",
        parameters=_obj(
            properties={
                "path": {"type": "string", "description": "Note relative path to delete"},
            },
            required=["path"],
        ),
    ),
    ToolSpec(
        name="unlink_notes",
        description="Remove a link from one note to another.",
        parameters=_obj(
            properties={
                "from_path": {"type": "string", "description": "Source note path"},
                "to_path": {"type": "string", "description": "Target note path to unlink"},
            },
            required=["from_path", "to_path"],
        ),
    ),
    ToolSpec(
        name="create_note",
        description=(
            "Create a new note the user can browse in the app. "
            "Use for full content, lists, research summaries, or when the user confirms saving. "
            "Do NOT use for small durable facts — use update_memory instead."
        ),
        parameters=_obj(
            properties={
                "title": {"type": "string", "description": "Note title shown in the app"},
                "body": {"type": "string", "description": "Note body in markdown"},
                "tags": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Optional tags",
                },
                "type": {
                    "type": "string",
                    "description": "Note type e.g. Note, Idea, Task",
                },
            },
            required=["title", "body"],
        ),
    ),
    ToolSpec(
        name="link_notes",
        description="Create a link from one note to another in the knowledge graph.",
        parameters=_obj(
            properties={
                "from_path": {"type": "string", "description": "Source note relative path"},
                "to_path": {"type": "string", "description": "Target note relative path"},
            },
            required=["from_path", "to_path"],
        ),
    ),
    ToolSpec(
        name="propose_idea",
        description="Record a proposed idea as a note of type Idea.",
        parameters=_obj(
            properties={
                "title": {"type": "string", "description": "Idea title"},
                "body": {"type": "string", "description": "Idea description"},
            },
            required=["title", "body"],
        ),
    ),
    ToolSpec(
        name="generate_image",
        description=(
            "Generate an image for the chat from a text prompt. "
            "Use when the user asks to draw, illustrate, visualize, restyle a photo, "
            "or produce a picture in any language. "
            "MUST call this in the same turn — never paste ![alt](http...) or sandbox image links. "
            "Do NOT use for documents or web search. "
            "When the user wants their look in the style of a note photo: the user's chat "
            "photo is already visible; set style_reference_path to the note .md path "
            "(preferred) or attachments/foo.png from read_note — do not paste style prose "
            "into prompt. Call read_note in an earlier tool round before generate_image."
        ),
        parameters=_obj(
            properties={
                "prompt": {
                    "type": "string",
                    "description": "Detailed image generation prompt",
                },
                "title": {
                    "type": "string",
                    "description": "Optional title when save_to_notes is true",
                },
                "save_to_notes": {
                    "type": "boolean",
                    "description": "Also save the image as a Photo note",
                },
                "style_reference_path": {
                    "type": "string",
                    "description": (
                        "Note .md path (preferred; uses first image attachment) or bundle "
                        "attachment path e.g. attachments/photo.png whose visual style should "
                        "inspire the generated image. Obtain paths from read_note attachments "
                        "list or read_note_attachment. Use in a later tool round after read_note."
                    ),
                },
            },
            required=["prompt"],
        ),
    ),
    ToolSpec(
        name="enrich_note",
        description=(
            "Enrich a note with AI-generated content: illustration for Idea, "
            "caption for Photo. Returns path of generated child note."
        ),
        parameters=_obj(
            properties={
                "path": {"type": "string", "description": "Source note path"},
                "kind": {
                    "type": "string",
                    "description": "Enrichment kind: idea or photo (default from note type)",
                },
            },
            required=["path"],
        ),
    ),
    ToolSpec(
        name="list_due_notes",
        description=(
            "List notes due for spaced-repetition resurfacing. "
            "Use when the user asks what to review or revisit today."
        ),
        parameters=_obj(
            properties={
                "limit": {"type": "integer", "description": "Max results (default 20)"},
            },
            required=[],
        ),
    ),
    ToolSpec(
        name="mark_note_done",
        description=(
            "Mark a note, task, or idea as done (or reopen it with done=false). "
            "Done notes stay searchable for you but are excluded from the user's "
            "review queue. Use when the user says they finished something "
            "(e.g. completed a shopping list or task)."
        ),
        parameters=_obj(
            properties={
                "path": {"type": "string", "description": "Note relative path"},
                "done": {
                    "type": "boolean",
                    "description": "true to mark done (default), false to reopen",
                },
            },
            required=["path"],
        ),
    ),
    ToolSpec(
        name="mark_note_resurfaced",
        description=(
            "Mark a note as resurfaced after showing it to the user during review. "
            "Call after presenting a due note from list_due_notes so it is not due again immediately."
        ),
        parameters=_obj(
            properties={
                "path": {"type": "string", "description": "Note path that was reviewed"},
            },
            required=["path"],
        ),
    ),
    ToolSpec(
        name="append_to_note",
        description=(
            "Append text to an existing note body without replacing existing content. "
            "Prefer over update_note when the user asks to add or append a paragraph."
        ),
        parameters=_obj(
            properties={
                "path": {"type": "string", "description": "Note path to append to"},
                "text": {"type": "string", "description": "Text to append"},
                "separator": {
                    "type": "string",
                    "description": "Separator before appended text (default blank line)",
                },
            },
            required=["path", "text"],
        ),
    ),
    ToolSpec(
        name="read_chat_attachment",
        description=(
            "Read an attachment from an earlier chat message (image description or document text). "
            "NOT for images the user just attached this turn — those are already visible. "
            "Use with session_id and attachment_path from search_chat_history or session metadata."
        ),
        parameters=_obj(
            properties={
                "session_id": {
                    "type": "string",
                    "description": "Chat session id (defaults to current session when omitted)",
                },
                "message_id": {
                    "type": "string",
                    "description": "Optional message id that owns the attachment",
                },
                "attachment_path": {
                    "type": "string",
                    "description": "Stored attachment filename in the session",
                },
            },
            required=["attachment_path"],
        ),
    ),
    ToolSpec(
        name="append_attachment_to_note",
        description="Copy a chat message attachment into an existing note.",
        parameters=_obj(
            properties={
                "note_path": {"type": "string", "description": "Target note path"},
                "session_id": {"type": "string", "description": "Chat session id"},
                "attachment_path": {
                    "type": "string",
                    "description": "Stored attachment filename in the session",
                },
            },
            required=["note_path", "session_id", "attachment_path"],
        ),
    ),
    ToolSpec(
        name="web_search",
        description=(
            "Search the public web for current or factual information. "
            "Use for local recommendations (restaurants, cafes, shops), weather, events, "
            "prices, recent news, or anything not in the user's notes. "
            "When location is shared, include the place label in the query "
            "(e.g. 'restauracje Pabianice'). The server expands local queries automatically. "
            "Never refuse current external info — call this tool. "
            "Set save_as_note=true when the user wants results saved as a Research note."
        ),
        parameters=_obj(
            properties={
                "query": {
                    "type": "string",
                    "description": (
                        "Web search query; include city/area for local or nearby requests"
                    ),
                },
                "save_as_note": {
                    "type": "boolean",
                    "description": "Save results as a Research note",
                },
            },
            required=["query"],
        ),
    ),
    ToolSpec(
        name="generate_document",
        description="Generate a PDF, Word (docx), or PowerPoint (pptx) document from an outline.",
        parameters=_obj(
            properties={
                "format": {
                    "type": "string",
                    "description": "Output format: pdf, docx, or pptx",
                },
                "title": {"type": "string", "description": "Document title"},
                "outline": {"type": "string", "description": "Document outline or content"},
                "save_to_notes": {
                    "type": "boolean",
                    "description": "Also save as a note with download link",
                },
            },
            required=["format", "title", "outline"],
        ),
    ),
    UPDATE_MEMORY_TOOL,
    ToolSpec(
        name="search_chat_history",
        description=(
            "Search earlier messages in the current chat session by keyword. "
            "Use when the user refers to something said earlier in this conversation "
            "that is not visible in recent messages."
        ),
        parameters=_obj(
            properties={
                "query": {
                    "type": "string",
                    "description": "Keyword or phrase to find in this session",
                },
                "max_results": {
                    "type": "integer",
                    "description": "Maximum matching snippets to return (default 5)",
                },
            },
            required=["query"],
        ),
    ),
    ToolSpec(
        name="create_playbook",
        description=(
            "Save a reusable multi-step procedure as a Playbook skill note. "
            "NOT for one-off facts (update_memory) or general notes (create_note)."
        ),
        parameters=_obj(
            properties={
                "name": {"type": "string", "description": "Playbook name"},
                "steps": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Ordered procedure steps",
                },
            },
            required=["name", "steps"],
        ),
    ),
    ToolSpec(
        name="update_playbook",
        description="Append a step to an existing Playbook by path.",
        parameters=_obj(
            properties={
                "path": {"type": "string", "description": "Playbook note relative path"},
                "step": {"type": "string", "description": "Step text to append"},
            },
            required=["path", "step"],
        ),
    ),
]
