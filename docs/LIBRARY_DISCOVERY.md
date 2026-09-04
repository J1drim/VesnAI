# Library organization and discovery

Pins and archive are synced OKF metadata (`vesnai.pinned` and `vesnai.archived`).
Archive is separate from task completion. Use the reader's action menu to change
either state, then Library/Pinned/Archive to browse. Saved views retain query,
tag, type, completion visibility and sort order on this device; the notes and
their organization metadata sync, while view names/preferences remain local.

Offline search uses SQLite FTS5 (schema 9) with Unicode word-prefix matching,
title/tag-weighted ranking and literal query tokens. It does not interpret typed
text as SQL or FTS operators. Filters are applied before pagination; Load more
extends results in batches of 100. Pin priority comes before the chosen ordering.
Triggers keep the index in the same transaction as notes; migration backfills
existing notes. Implementation follows [SQLite's FTS5 documentation](https://www.sqlite.org/fts5.html).

The search-field sparkle opens a separate, explicitly run semantic search.
This uses the paired server's existing embedding index, never web research.
Unavailable services and fake/demo embeddings are not presented as valid
semantic results. Related-note suggestions explain their similarity and require
an explicit Link action. Incoming/outgoing links are available offline in the
reader. Markdown links remain body links instead of being duplicated into
permanent explicit metadata when a note is parsed.

## Host scale baseline

Run on the available macOS development host with Flutter 3.44.0, Dart 3.12.0,
native SQLite in memory, 10-paragraph synthetic notes, 20 query samples per size.
These are debug/test-host timings, not phone measurements or frame-time claims.
Writes are batched in one transaction. Initial insertion includes cold SQLite
startup, making the first small sample unsuitable for a linear scaling claim.

| Notes | Search median | Search p95 | Load full catalog | Build graph | Serialize sync docs |
|---:|---:|---:|---:|---:|---:|
| 100 | 1.32 ms | 3.44 ms | 4 ms | 3 ms | 1 ms |
| 1,000 | 1.22 ms | 1.44 ms | 4 ms | 14 ms | 5 ms |
| 10,000 | 5.50 ms | 6.25 ms | 61 ms | 125 ms | 38 ms |

At 10,000 notes, full-catalog/graph work still warrants care on mobile; search is
paginated and layouts are lazy, but this is not a claim that the graph animation
or end-to-end network sync has been optimized for a 10,000-node phone display.
Physical scrolling/frame times and network sync latency remain release checks.

Reproduce with:

```sh
flutter test --no-pub --dart-define=BENCHMARK_LIBRARY=true test/performance/library_benchmark_test.dart
```
