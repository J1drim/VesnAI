# Sync and metadata ownership

New clients submit `base_version`: zero for a new path, otherwise the last
acknowledged/downloaded server version. Each accepted edit gets the next server
version; repeated identical content is acknowledged without another revision.
Deletions require a matching base too. A stale edit of a deleted path is rejected.
Clients upgrading with an already-pending legacy edit omit an unknown base.

An `applied` path is the acknowledgement. `versions` contains canonical accepted
versions. Conflicts include the server document/version when available and a
unique recovery-copy path for divergent documents. The client retains conflicts
and unacknowledged changes; it never treats a successful HTTP response alone as
proof an edit is safely synced. Legacy uploads without a base retain the old
winner selection but now preserve every divergent losing version.

Network sync is serialized per client; local saves remain possible during a
request. An acknowledgement clears only the exact submitted local revision.
The mirror applies a pulled batch and its cursor in one SQLite transaction.
Pending edits are not overwritten by downloads. Bundle mutations are serialized
within the server process, including attachment writes and imports. Deploy one
writer process per bundle; this lock is not a distributed/multi-worker lock.

The note model retains unknown frontmatter, including nested `vesnai` extensions.
On an existing path the server preserves ID, creation time, profile version and
version vector; client edits own title, body, type, tags, explicit links, completion,
pins and archive. Unknown fields are merged, not deleted by older clients. An
explicit false completion removes the previous completion timestamp.

Recovery actions check the latest server revision. Keep mine queues the local
edit (or deletion) against it. Keep server replaces only the local mirror. Keep
both creates a new local note and adopts the current server note. Another remote
edit between resolution and upload produces another conflict, never a forced
overwrite. Recovery requires connectivity and does not discard the local copy
if the server cannot be reached. Attachments keep their existing references.
