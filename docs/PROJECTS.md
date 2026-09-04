# Saved views as project spaces

The folder action beside library filters opens saved views as projects. An
overview uses the same offline query/tag/type/status/archive filters and shows
notes, open tasks and research counts. The overview previews 100 notes; the saved
library view remains the full browsing surface. Scope is bounded at 10,000 notes.

“Ask about this project” is explicit, read-only and requires a real chat provider.
Pending local notes must sync first. Each request passes an explicit note-path
allow-list and the view filters; the server intersects those with its current
notes. Deleted, reserved, conflicting, newly out-of-scope and transcript paths
are excluded. Markdown attachments are not indexed as independent notes.

Retrieval is deterministic lexical ranking, not a claim of semantic search:
at most eight excerpts of 3,000 characters enter the model context. Responses
show the evidence/scope counts and clickable in-range citations emitted by the
model. Citation existence does not prove a model’s claim; inspect the source.
No ordinary assistant tools, web access, memory or global library retrieval are
available to this endpoint. Demo and unavailable providers are clearly reported.

The last 100 turns persist locally per saved-view configuration. Follow-ups
include the four preceding questions, but not earlier assistant answers: a
changed project membership must not reintroduce excluded note content through
old answers. Displayed older answers remain historical and can become stale.
Renaming/changing a saved view starts a separate local conversation.

Verified with an offline filtered-overview widget test and authenticated server
tests checking scope intersection, excluded content, empty scopes, unavailable
demo mode, no tools, and citation-path validation. Live-model answer quality
still depends on the configured provider and was not tested here.
