# Mobile sharing inbox

Android accepts shared text/Markdown, URLs, images and PDFs through Send/Send
multiple. iOS has a Share extension for text, URLs, images and files. Both copy
incoming files into private durable storage before acknowledging the sender;
limits are ten attachments, 50 MB total and one million text characters.

On launch/resume, VesnAI imports each item into an offline note tagged `inbox`,
preserves the first HTTP(S) URL as source, and copies attachments into the durable
capture cache. Open Inbox from the library toolbar to review or file notes away.
This does not replace an unfinished editor draft. Article extraction is not
automatic: the shared text and original attachments are retained as received.

Native items are removed only after a local note is saved. Deterministic note
paths make retries safe even if acknowledgement failed or that note was edited.
Exact duplicates are ignored; changed content from the same source is retained
with a link to the earlier capture. A failed import stays in the native inbox:
retry it or explicitly confirm discarding the private pending copy. Other queued
items resume after that item succeeds or is discarded. Original sender files
are never deleted. Media uploads use the existing persistent sync queue.

## Platform setup and release checks

The iOS Runner and ShareExtension targets both require provisioning for App Group
`group.ai.vesnai.shared`; select the appropriate signing team/profile in Xcode.
The extension saves into the group container and completes the share sheet;
open VesnAI normally to import it. It does not force the containing app to open.
The extension targets iOS 15, matching the existing app deployment baseline.
The unsigned CI build checks compilation, not provisioning or device behavior.

Android only accepts granted content URIs, rejecting private file URIs and its
own file provider. Filename extensions and acknowledgement IDs are validated;
incoming streams are copied off the UI thread. iOS bounds each copy and does not
accept its own shared-container files as external inputs.

Validation: Flutter offline/replay/duplicate tests, 11 Android native share/widget
tests and an Android release APK pass locally. Swift syntax and project/plist
checks pass; the full iOS extension build runs in macOS GitHub CI. Before a signed
release, share text, a browser URL, an image and multiple files on both platforms;
repeat with the app terminated, offline, resumed, and with denied permissions.
Check over-limit/error recovery and App Group provisioning on a physical iPhone.

Platform references: [Android receiving shared content](https://developer.android.com/develop/ui/compose/sharing/receive)
and [Apple extension data sharing](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html).
