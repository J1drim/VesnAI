# VesnAI upgrade plan

Prepared 2026-09-04; implementation authorized 2026-09-05. The sections below
retain the agreed scope. Delivery status is tracked separately in
[UPGRADE_PROGRESS.md](UPGRADE_PROGRESS.md).

## Recommended direction

Build on VesnAI's calm spring palette, rounded cards, and personal assistant identity. Prioritize reliable capture, finding existing knowledge, and comfortable reading. Remove age-based note reminders completely. Add organization and contextual discovery in small releases, using the existing Markdown store, offline mirror, graph, and AI services.

The recommended first release combines reminder removal, sync reliability work, dependency updates, usable desktop cards, and a modest visual polish pass. Start dependency triage before implementation so urgent fixes and required SDK changes inform the work. Saved views and better search should follow before larger AI features.

## Review basis and current strengths

Reviewed the Flutter client, Python server, storage/sync path, reminder lifecycle, theme, note list/detail/desktop views, graph, search, settings, tests, and CI configuration. Visually inspected the committed note-list golden image. That image uses test glyphs rather than readable production typography; this is a code and fixture review, not a live-device visual audit or performance benchmark.

Existing capabilities worth extending:

- Local capture and editing, a Drift/SQLite mirror, queued sync, and portable OKF Markdown backed by Git.
- Rich text, checklists, attachments, photos, drawing, voice capture, and native widgets.
- Persistent AI conversations, note tools, generated images, Marena critiques, and multilingual web research.
- An embedding index that already chunks long content, plus a graph with filters, local data, and persisted layout.
- English/Polish localization, light/dark themes, generated-content labels, device pairing, and backup/restore.

These are existing features, not proposed additions. The gaps below concern usability, reliability, and making those capabilities easier to access.

## Findings that shape the priorities

| Finding | Evidence | Implication |
|---|---|---|
| Reminders use elapsed time rather than relevance. | `server/vesnai/ai/selftune.py`: intervals `[1, 3, 7, 16, 35, 90]`; `app/lib/data/notifications_feed.dart`: daily 09:00 scheduling. | Remove both resurfacing and scheduled notifications, including notifications already registered with the OS. |
| Desktop cards have no open/edit interaction. | `app/lib/desktop/sticky_board.dart`: `StickyNoteCard` returns a display-only container; the add action immediately captures an empty note. | Make desktop capture and reading usable before extending the board. |
| Client sync ignores per-note push results. | `app/lib/data/sync_queue.dart`: the response from `client.push()` is discarded before all submitted notes are marked synced. | Rejections and conflicts need explicit handling and user-visible recovery. |
| A pull cursor is persisted before downloaded changes are applied. | `SyncEngine.flush()` calls `store.setCursor(cursor)` before its change loop. | A crash or apply failure could skip unapplied changes; apply the batch and cursor in one transaction. This failure scenario was identified by inspection, not reproduced. |
| Equal-version edits can replace different content without a conflict result. | `server/vesnai/sync.py`: `_resolve()` compares version and timestamp; a direct probe confirmed `conflict=False` for different bodies at version 2. | Define concurrency using an explicit base revision or validated version vectors. The current implementation does not use vectors in conflict resolution despite the module description. |
| The note model reconstructs a limited set of metadata. | `app/lib/models/note.dart`: `toConcept()` emits selected fields; fields such as original creation time, IDs, vectors, and arbitrary extensions are not retained in the model. | Establish metadata ownership and preservation before adding pins, archive state, or collections. Audit server sync round trips as part of this work. |
| Library search is a simple substring scan. | `app/lib/features/notes/note_search.dart`; `LocalNoteStore.all()` loads the catalog. | Improve offline search, ranking, and filters; expose the existing semantic index through a dedicated library-search workflow. |
| Both note layouts eagerly create their child widgets. | Mobile uses `ListView(children: [...visible.map(...)])`; desktop uses `SingleChildScrollView` and `Wrap`. | Use lazy lists/grids and measure a larger library before adding more content to every card. |
| The theme is intentionally small and mostly uses Material defaults. | `app/lib/theme.dart` defines a green seed, type colors, generated accent, and a small card override. | Shared typography, spacing, surfaces, and component states can improve consistency without changing the identity. |
| The named nightly CI job is unreachable under the current triggers. | `.github/workflows/ci.yml` triggers only on push/PR, while `e2e_nightly` requires schedule/manual dispatch. Its steps run Python live tests, not Flutter E2E. | Correct triggers and distinguish automated offline checks, device E2E, and tests that actually need model infrastructure. |

## 1. Remove note reminders — first release

Treat this as removal of the complete age-based review feature, including its notes section and assistant tools. Keep task completion, ordinary note retrieval, assistant memory consolidation, and notifications for requested work finishing.

### Client changes

1. Remove the “Due for review” section, its loading state, and review-on-open calls from `app/lib/features/notes/notes_screen.dart`.
2. Remove `refreshDueReviewReminder()` and its launch/resume calls from `app/lib/data/notifications_feed.dart` and `app/lib/app.dart`.
3. Add an idempotent upgrade cleanup that cancels legacy notification ID **900001** locally. Run it on launch regardless of pairing or connectivity, before any obsolete scheduling can run. Retain it for users upgrading directly from older versions, and retry if cancellation fails. Cleanup must not request a new notification permission merely to cancel an old reminder.
4. Remove daily scheduling from `JobNotifier`, `LocalNotifier`, and test doubles once the cleanup path is in place. Keep notification delivery for chat/research/image/critique completion and keep the background job poller.
5. Handle old `due_review` notification taps safely by opening Notes with no review section. Keep this small compatibility mapping while old notifications can exist.
6. Remove reminder-specific English/Polish strings; regenerate localization output. Adjust explanatory text that currently ties “Done” to a review queue.
7. Audit `timezone`, `flutter_timezone`, Android scheduled-notification receivers, and associated boot configuration. Remove only reminder-exclusive dependencies/configuration after testing upgrades and reboot behavior. Regenerate plugin registrants through the normal Flutter workflow; retain configuration required by background polling.

### Server changes

- Remove `ResurfacingScheduler`, its initialization in `app_state.py`, and the due-note/mark-resurfaced helper wiring.
- Remove `list_due_notes` and `mark_note_resurfaced` from tool schemas, dispatch, and prompt instructions. Search tool policies, tests, and documentation for references. Keep `mark_note_done`, and revise its description to reflect completion rather than review scheduling.
- For a transition release, keep authenticated `/v1/notes/due` returning an empty list and `/v1/notes/{path}/resurfaced` as a harmless compatibility response that does not write metadata. Remove the endpoints after paired clients have migrated. New clients must work with old servers by never requesting review data.
- Leave existing `resurface_count` and `last_resurfaced` metadata inert; no bulk rewrite or deletion of user notes is needed.
- Preserve the separate assistant memory-review process and other useful components in `selftune.py`.

### Completion criteria

- Upgrading an installation with a pending reminder cancels it even in airplane mode or when unpaired.
- Launch, resume, reboot, and advancing a test clock by 100 days produce no new age-based reminder.
- No due-review UI or review tools appear; legacy notification taps and transitional endpoints remain safe.
- Normal completion notifications, note editing, checklists, and Done/Reopen still work.
- Fixtures containing old review metadata continue to load and sync.

An old installed client can continue firing its locally scheduled reminder until it launches online against the transitional endpoint or receives the client upgrade. A server-only change cannot reliably cancel an offline device's OS notification.

## 2. Reliability and recovery — first release foundation

Make sync acknowledgements accurate before adding more synced metadata.

- Serialize overlapping flushes. Track the revision submitted for each note so completion of an older request cannot overwrite or mark a newer local edit as synced.
- Parse `applied` and `conflicts`; retain rejected edits and offer “Keep mine”, “Keep server”, and “Keep both” with readable previews. Make repeated conflict copies unique; the current `.conflict-{device}.md` name can be reused.
- Apply pulled changes and the cursor transactionally. Reconcile downloads with edits made while a request was in flight.
- Specify base-revision/concurrency semantics across client and server, including deletion versus editing. Preserve both versions when causality is unknown; do not rely solely on device timestamps.
- Preserve unknown OKF frontmatter and server-owned fields across edits. Decide which fields the server merges and which the client can change, then test the complete round trip.
- Add a compact sync status with pending count and actionable failures. Existing pending icons and last-sync text are useful starting points.

Acceptance scenarios: two devices edit the same base revision offline; editing continues during upload; a push rejects one note in a batch; applying a pull fails partway through; a deletion races an edit; and custom metadata survives a client edit. No unsent edit should be labelled safely synced or lost when rebuilding a mirror.

## 3. Visual evolution — first release, then desktop refinement

### Keep the recognizable identity

Retain the green seed (`#2E7D5B`), mint/teal tasks, warm gold ideas, lavender photos, purple generated-content accent (`#8E6BD6`), logo, and rounded cards. Keep Marena recognizable, but reserve large error-red surfaces for actual failures. Existing light and dark modes should both receive the refinements.

### Proposed refinements

| Surface | Proposed treatment | Benefit |
|---|---|---|
| Notes header | A clear page title, quiet sync status, one search field, and a compact filter row. | Frees space and gives the library a calmer hierarchy after removing review content. |
| Note cards | Stronger title weight, a restrained preview, optional small thumbnail, and one compact metadata row for tags/update state. Cap tags and use `+N`. | Makes scanning easier without turning every card into a dashboard. |
| Cards and controls | Define shared spacing, corner radii, input/button styles, focus/hover states, and light/dark surface tokens in the theme. | Makes the app feel deliberately designed across screens. |
| Note reader | Center a readable-width column on large windows; keep the title dominant and secondary metadata quieter. Move less frequent actions into a menu. | Improves reading comfort and reduces toolbar crowding. |
| Desktop shell | Use available window width to switch from bottom navigation to a navigation rail; allow list/grid choice and, later, an adjacent note reader. | Uses desktop space while retaining the mobile experience. |
| Desktop cards | Open on click/Enter, support keyboard focus, and route Add through capture. Replace fixed 200×200 sizing with responsive grid constraints. | Gives the existing sticky-board appearance useful interactions. |
| Chat | Improve reading width and message spacing; make existing action results, sources, retries, and attachments easier to scan with compact expandable sections. | Clarifies long answers and background work. |
| Empty/loading states | Small branded icon, useful next action, and restrained progress feedback. Preserve content during refresh where possible. | Reduces abrupt layout changes and makes first use clearer. |

Use existing type/icons alongside color, and check contrast rather than assuming the palette passes everywhere. Respect reduced motion and large text. Add a persisted System/Light/Dark preference; themes already exist, so this is a control and consistency improvement.

Visual acceptance: real-font screenshots of Notes, detail, chat, and desktop board in light/dark, English/Polish, a narrow phone and wide/resized windows; long titles and large text do not overflow; keyboard focus is visible. Update goldens after the new appearance is reviewed. No new illustrations or image-generation dependency is needed for this pass.

## 4. Additional features, in recommended order

Effort is relative: **S** = a contained change; **M** = several screens/layers; **L** = a protocol, data migration, or substantial native integration. These are planning estimates, not delivery commitments.

| Priority | Feature | Smallest useful version and acceptance | Effort / dependency |
|---|---|---|---|
| Next | Pins, archive, and saved views | Pin important notes; archive reference material without marking it Done; save combinations of tags/type/status and sort order. Start “collections” as saved tag views. State survives restart and syncs where intended. | M; metadata preservation and migration first. |
| Next | Better library search | Offline indexed text search with highlighted matches, filters, and ranking; add an explicit semantic search option backed by the existing server index. Keep external web research a clearly named action. Offline queries never require the server. | M–L; searchable store API, indexing and search endpoint. |
| Next | Related notes and backlinks | A section in note detail showing explicit incoming/outgoing links offline. Add a few semantic suggestions when available, with a reason and “Link” action. Suggestions do not modify notes automatically. | M; reuse graph/link resolution and embeddings. |
| Next | Capture drafts and templates | Persist an unfinished capture; add lightweight meeting, idea, and reading-note templates; offer app-level new-note/search/save shortcuts on desktop. Reopening after process termination restores the draft and attachments. | M; local draft lifecycle and attachment cleanup. |
| Later | Note history and Trash | View per-note revisions and restore a revision as a new edit. Add recoverable deletion with attachment/child-note handling and an explicit retention policy. Restore an item and its media from another device. | L; sync deletion semantics and Git-backed revision API. |
| Later | Project spaces and scoped chat | Start from saved views: a project overview shows related notes, open tasks, and research. “Ask about this project” uses the selected scope and opens cited notes. | M–L; saved views and filtered retrieval first. |
| Later | Share-to-VesnAI and clipping | Receive shared URLs/text/files on mobile and capture them to an offline inbox with source metadata and duplicate detection. Add article extraction only as a separate step. | L; native entry points and ingestion lifecycle. |
| Later | Useful graph navigation | Search for a node, focus its immediate neighborhood, display a preview before opening, and offer fit/reset controls. Keep current filters/layout persistence. | M; existing graph implementation. |
| Optional | Library cleanup assistant | On request, suggest duplicates, inconsistent tags, and broken links. Show a preview and let the user apply each change. No automatic merges or scheduled nags. | M; search, history, and recovery first. |

The best replacement for resurfacing is **contextual discovery**: show useful connections while a note is open or a question is being answered. Pins and saved views cover deliberate “come back to this” intent. There is no need to add another scheduled review queue.

## 5. Supporting engineering upgrades

- **Scale the library:** move both layouts to lazy builders; add query/pagination support to the local store; benchmark representative libraries of 100, 1,000, and 10,000 notes on an agreed device. Record search latency, scroll behavior, graph cost, and sync time before setting optimization targets.
- **Improve completion delivery:** notifications currently have a global `read` flag in `server/vesnai/notifications.py`, foreground polling runs every five seconds, and foreground/background consumers can overlap. Define per-device delivery versus owner-wide read state, persist event IDs for deduplication, and use atomic storage. Verify bursts do not collide under the current second-based local notification IDs. Consider the existing SSE endpoint with reconnect/polling fallback only after delivery semantics are clear.
- **Give AI controls useful visibility:** expose current image/critique behavior and notification preferences in Settings where supported; allow costlier optional enrichment to be requested explicitly. Show actual service availability separately from demo/fake-provider mode. Avoid increasing background generation as part of visual polish.
- **Make CI evidence match documentation:** add intended manual/scheduled triggers and a real device E2E job when infrastructure exists; keep tests requiring real models explicitly opt-in. Replace the `or True` assertion in `test_pull_returns_deltas_after_cursor` with a meaningful delta assertion. Make analyzer failures fail reliably rather than relying only on text filtering. Update README test/coverage claims from verified results.
- **Reduce maintenance friction incrementally:** split growing provider, chat, and API modules along feature boundaries when those areas are changed. Keep shared note presentation consistent between mobile and desktop. Do not make a repository-wide rewrite a prerequisite.

## 6. Dependency updates and Dependabot — first release and ongoing

Dependency upgrades are an explicit deliverable, with an initial backlog cleanup followed by regular maintenance. Reuse the existing Dependabot setup in `.github/dependabot.yml`: weekly updates already cover the Flutter app (`/app`), shared Dart package (`/packages/okf_dart`), Python server (`/server`, configured as `pip`), and GitHub Actions. Current open-PR limits are 5, 3, 5, and 3 respectively.

The local configuration was inspected, but open GitHub PRs, security alerts, and Dependabot update logs were not queried during this planning update. No specific package version or vulnerability is asserted here.

### Initial upgrade pass

1. Inventory open Dependabot PRs, update failures, and security alerts on GitHub. Compare them with resolved dependencies in `app/pubspec.lock`, `packages/okf_dart/pubspec.lock`, and `server/uv.lock`, plus fresh outdated/audit reports. Include transitive dependencies and verify that the server's configured update job actually updates its uv-managed lockfile.
2. Prioritize applicable security fixes and unsupported dependencies, then compatible patch/minor updates. Schedule major upgrades individually or as a tightly related package family after reviewing migration guides and release notes. Record the reason and next review date for a deferred update.
3. Upgrade coupled packages together where required: Drift and its generator, editor/native bridge dependencies, and plugins with shared Flutter/Dart or platform constraints. Commit manifests, lockfiles, and necessary regenerated code together; verify a clean checkout installs the committed resolution without unexpected lockfile changes.
4. Review the existing `file_picker` beta and `package_info_plus` / `quill_native_bridge_windows` overrides. Replace temporary workarounds with compatible stable releases when available and tested; document any override that remains. Include Flutter/Dart, Python, Android build tooling, and Apple/Windows build requirements in the compatibility check.
5. Validate Python optional environments separately. Preserve the declared image/Chatterbox conflict: test core+dev, the supported AI stack, and each relevant image or voice combination in isolated environments. Do not attempt one environment with every extra installed. Check license implications of changed AI/media dependencies.
6. Coordinate notification dependency changes with reminder removal. Remove reminder-only packages after legacy cancellation is verified; validate the retained notification and background-work packages against upgraded-installation behavior.
7. Review dependency coverage outside the four configured jobs: Docker images/digests, the Compose image lock register, native platform dependencies, and runtime-installed tools such as mflux. Add supported automation or an explicit periodic review for each gap. Review mutable image tags and record tested versions/digests for reproducible releases.

### Dependabot workflow

- Keep weekly version-update checks and triage the existing PR backlog weekly. Handle applicable security alerts promptly rather than waiting for the next feature milestone; verify GitHub security-update settings separately from the committed schedule.
- Group compatible patch/minor updates by ecosystem or closely related package family to reduce PR noise. Keep breaking changes and high-impact storage, editor, notification, or native-plugin upgrades independently reviewable when they need different validation.
- Rebase or refresh affected Dependabot PRs after each merge; use their latest CI results. Track blocked updates so the open-PR limits do not leave the same backlog unattended.
- Require the relevant checks before merging. Initially use reviewed merges; consider automatic merging only later for narrowly defined low-risk updates once CI covers their behavior.
- Keep dependency PRs separate from unrelated feature changes, and record meaningful migrations or compatibility constraints in the changelog. Prefer reproducible installs in CI and maintain a known-good lockfile/build to support rollback.

### Validation and completion criteria

| Update area | Required evidence before release |
|---|---|
| Flutter / shared Dart | Analyze, shared OKF tests, app unit/widget/golden tests, and builds for affected release platforms. Exercise editor round trips, attachment picking, offline storage/sync, or voice depending on the changed packages. Review visual differences after framework upgrades. |
| Notifications / background work | Upgrade an existing installation with a scheduled reminder; verify cancellation, ordinary completion notifications, permissions, background delivery, and restart/reboot behavior on affected platforms. |
| Python server | Lint, types, full offline tests, lockfile consistency, and dependency/license checks. Run targeted provider smoke tests for changed optional integrations, explicitly recording unavailable live-model checks. |
| GitHub Actions / build tools | Successful affected workflows with the intended runner/runtime versions and permissions; generated release artifacts still build. |
| Containers / runtime tools | Startup and service health, API compatibility, persisted-data compatibility, and a documented rollback path. Use a copy of data for migration checks. |

The initial pass is complete when each current Dependabot PR and applicable alert has a disposition, selected upgrades are merged with their checks passing, lockfiles are consistent, and deferred major/blocked updates have a reason and a follow-up task. The existing `scripts/check_flutter_deps.py` only checks for direct Flutter packages lagging by two major versions; supplement it with security and compatibility checks rather than treating it as a complete dependency audit. Effort is **M** for a compatible backlog cleanup and **L** if major SDK/native migrations are required; refine this after inspecting the live backlog.

## Delivery sequence and release gates

| Milestone | Scope | Gate |
|---|---|---|
| Dependency baseline — start before A | Triage Dependabot PRs/alerts, identify SDK constraints, and select compatible updates. Apply urgent fixes first; continue routine updates alongside later milestones. | Backlog has dispositions; chosen versions and required migrations are documented; relevant checks pass for each update. |
| A — Quiet, trustworthy basics | Remove reminders; cancel legacy schedules; correct sync acknowledgement/cursor/concurrency handling; complete selected dependency updates; make desktop cards open and capture correctly. | Upgrade/offline notification checks and multi-device sync scenarios pass; dependency validation gates pass; no silent edit loss in those scenarios. |
| B — Polished daily use | Theme tokens, card/reader refinement, responsive navigation, lazy layouts, draft persistence, keyboard support. | Real-font visual checks across target sizes/languages/themes; offline draft recovery; baseline performance measured. |
| C — Find and organize | Pins/archive/saved views, improved offline search, explicit semantic search, backlinks and related notes. | Metadata migration round trips; offline search works; suggestions have provenance and never create links without an action. |
| D — Deeper workflows | Note history/Trash, then project-scoped chat, sharing/clipping, and focused graph navigation. Select these according to actual use after A–C. | Recovery works across devices and attachments; project retrieval respects scope; native capture handles offline/retry cases. |

Implement reminder removal, sync fixes, and dependency updates as separate reviewable changes inside milestone A. Settle any selected Flutter/editor upgrade before approving new visual goldens to avoid repeating the polish pass. Visual work can be developed against fixtures, but new synced fields should wait for metadata/sync corrections. Keep routine Dependabot maintenance active throughout B–D. No calendar estimate is assigned until the supported release platforms and milestone scope are fixed.

## Verification performed for this review

- Passed **25 existing Flutter tests** across `sync_queue_test.dart`, `sync_bootstrap_test.dart`, `notification_payload_test.dart`, `sticky_board_test.dart`, and `note_tile_test.dart` using `flutter test --no-pub`.
- Ran direct Python probes against the existing environment: a two-day-old note is selected for review; differing equal-version bodies resolve to the newer timestamp without a conflict flag. These probes do not touch stored user notes.
- Attempted the focused Python test suite, but `server/.venv` does not contain `pytest`; the server suite was not run. Existing dependencies were not replaced to perform a planning review.
- Did not run live AI services, a complete platform build matrix, performance benchmarks, or a live-device visual audit. Passing existing tests does not cover the missing concurrency/upgrade scenarios described above.

The verification above records the original planning review. See the progress
log for implementation changes and their validation.
