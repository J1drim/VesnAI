# History and Trash

Server deletion first writes a flushed ZIP snapshot under `.recovery/` in the
knowledge bundle. The snapshot includes the source note, generated caption/image
children, and referenced media. Only after the snapshot is durable are the
original notes deleted. Shared attachments still referenced by live notes stay
in place. Snapshots are excluded from note discovery and included in bundle
backups. Sync cannot write `.recovery` or `.git` internals.

There is **no automatic expiry**. Trash remains until explicitly discarded.
Discard removes the active recovery snapshot, not historical Git objects or
external backups; it is not a secure-erasure feature. Monitor disk usage,
especially with media-heavy libraries. Older clients still receive ordinary
deletion deltas; new clients access recovery through authenticated library APIs.

Any paired device can list and restore server Trash. The complete snapshot is
validated before writing: an existing note at an original path or differing
attachment bytes cause a conflict, never an overwrite. Interrupted restores
retain the snapshot and can safely resume. Restoration emits normal sync
changes, preserves note IDs and advances revisions. Restore on another device
then sync to retrieve its notes/media.

The deleting device also keeps a separate local safety copy, including notes
that never reached the server. Local copies restore as **new notes**, retaining
unsent content without reviving an old deletion against a newer server note.
Their media remains in application documents. They are clearly distinguished
from server snapshots in Trash; discarding one does not discard the other.
Local copies are not included in a server-only backup.

History lists the last 50 Git revisions for a note. Select one to preview its
title/body, then explicitly restore. The server checks the current base revision
and restores historical media and content as a new edit; it never resets Git.
Pending local changes must sync first. Missing or changed historical media is
reported rather than silently replacing files. History requires a Git-backed
server; local Trash still works offline.

Tests cover grouped child/media restoration, shared attachments, overwrite
conflicts, interrupted restore replay, revision concurrency and media recovery,
authenticated cross-device restoration, local unsent-note recovery and media
ownership after deletion acknowledgement. Native-device fault injection is
still a separate release check.
