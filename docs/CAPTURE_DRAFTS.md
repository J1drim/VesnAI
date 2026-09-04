# Durable capture

Capture automatically saves draft text, type, tags and source in the local
SQLite database. Attachment bytes are flushed to a content-addressed file in
the application documents directory before the draft references them. Opening
Capture again restores the unfinished note. Meeting, idea and reading templates
append to existing content; they do not replace it.

Save commits locally without waiting for a network connection. An attachment
outbox uploads content before pushing the note, verifies the returned SHA-256
identity, and retains failures for retry. This requires the upgraded server's
authenticated `/v1/library/attachments` endpoint. Older servers leave media
notes pending safely until upgraded. Ordinary text capture remains compatible.
Uploads retain the server's bounded request size and do not trigger automatic
AI enrichment. Use the existing explicit enrichment action after sync.

Draft clearing happens only after the note is durable. A crash between note
save and clearing reuses the saved path if the content is unchanged; if that
note has since been edited, capture creates a separate recovered note.
Discard asks for confirmation. Removed/discarded draft attachments are deleted
locally only when no draft, note, pending deletion or upload references them.
Unclaimed files left by a process dying between file creation and metadata
save are retained rather than risking deletion of unsent media.

On the home shell, Ctrl/Cmd+N opens Capture and Ctrl/Cmd+F opens/focuses library
search. Capture supports Ctrl/Cmd+S. Drafts and saved library views are local
to a device; saved notes and their media sync normally.

Automated coverage includes SQLite/cache close and reopen, draft/template
widget restoration, successful clearing after save, conservative attachment
cleanup, offline upload failure and retry order, and authenticated/idempotent
server uploads. These are process-boundary simulations, not physical-device
power-loss tests.
