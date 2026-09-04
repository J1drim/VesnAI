# Graph navigation and deliberate cleanup

Graph search matches note titles/paths within the current filters. Selecting a
result or tapping a node opens a preview before navigation. Focus connections
keeps the selected note and its incoming/outgoing one-hop neighbors. Show full
graph removes that focus without changing existing type/origin/tag filters.
Fit centers/scales the visible graph; reset restores a ring layout for visible
nodes. Persisting a focused/filtered layout preserves hidden node positions.

The cleanup action in library controls runs **only when requested**, entirely
offline. It detects identical non-trivial text (whitespace normalized), spelling
variants of existing tags, and missing Markdown-note links. It does not use an
LLM, automatically merge notes or schedule reminders.

Each suggestion is reviewed before applying. Duplicate text can be archived,
tag variants can be changed to the most common existing spelling, and broken
explicit links can be removed. Body links open the note for manual editing.
Before applying, the current note and suggestion are checked again; changed
evidence requires another scan. All applied changes use normal local-first sync,
so archive can be reversed and server-side edits remain in Git history.

Tests cover search → preview → neighborhood → full graph → fit/reset,
incoming/outgoing graph scope, hidden layout preservation, read-only suggestion
generation and explicit confirmation before a local queued change.
