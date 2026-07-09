# VesnAI OKF Profile

VesnAI stores all knowledge as an [OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog)
v0.1 bundle: a directory of Markdown files with YAML frontmatter. This document
defines the thin VesnAI profile layered on top of OKF. Per OKF's permissive rule,
consumers must tolerate unknown fields, so any OKF-aware tool can still read a
VesnAI bundle.

## Frontmatter

Standard OKF fields used: `type` (required), `title`, `description`, `tags`,
`timestamp`.

VesnAI namespaces its own fields under a single `vesnai` mapping:

```yaml
---
type: Idea
title: Trip to see the northern lights
tags: [idea, travel]
timestamp: '2026-01-15T09:30:00+00:00'
vesnai:
  id: 0192f0a0-0000-7000-8000-000000000001   # stable UUIDv7 note id
  profile_version: 1                          # VesnAI profile version
  origin: user                                # user | generated
  created: '2026-01-15T09:30:00+00:00'
  updated: '2026-01-15T09:30:00+00:00'
  version: 1                                  # monotonic edit counter
  version_vector: { server: 1 }               # per-device counters for sync
  links: [generated/idea-image.md]            # bundle-root-relative links
  attachments: [attachments/aurora.png]
  source: idea-northern-lights.md             # set on generated children
---
```

### Field semantics

- **origin** - `user` for things you wrote, `generated` for anything VesnAI
  produced (images, captions, research, chat transcripts, memories). Clients MUST
  visually distinguish `generated` content.
- **links** - bundle-root-relative paths. Body Markdown links are file-relative.
  Both feed the knowledge graph.
- **version / version_vector** - drive offline-first sync and conflict
  resolution (last-write-wins by version then `updated`).

## Reserved files

`index.md` (auto-generated directory listing) and `log.md` (append-only change
history) follow OKF reserved-file conventions and carry no `type`.

## Concept types used by VesnAI

`Note`, `Idea`, `Photo`, `GeneratedImage`, `GeneratedCaption`, `Research`,
`ChatTranscript`, `Memory`, `Playbook` (skills), `UserModel`. Types are not a
closed set; producers may add more and consumers treat unknown types generically.
