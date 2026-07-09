# Clients: mobile, desktop, and home-screen widgets

One Flutter codebase targets iOS, Android, macOS and Windows. The data layer
(`app/lib/data`) is shared by every surface; only the presentation adapts.

## Mobile

Bottom-nav shell with Notes / Chat / Graph / Settings (`app/lib/app.dart`).
Capture is offline-first: edits save to the local mirror immediately and queue
for sync (`SyncEngine`); they flush when the paired server is reachable.

The knowledge graph is computed on-device from the local note mirror
(`buildLocalGraph`); the app does not call the server graph API.

## Desktop (macOS / Windows)

`AdaptiveNotes` renders the `StickyBoard` (a wrapping board of sticky-note cards)
on desktop platforms instead of the mobile list, reusing the same providers and
sync. Build with `flutter build macos` / `flutter build windows`.

## Home-screen widgets

The app and the native widgets exchange a tiny serializable contract
(`app/lib/data/shared_storage.dart`):

- The app writes a **snapshot** (`{version, recents: [{title,type,generated}]}`)
  after each sync.
- Widgets read recents to display and write **quick captures** the app drains on
  next foreground.

### iOS (WidgetKit, Swift)

- Source: `app/ios/VesnaiWidget/VesnaiWidget.swift`; tests:
  `app/ios/VesnaiWidgetTests/VesnaiWidgetTests.swift`.
- Add a Widget Extension target in Xcode and enable the **App Group**
  `group.ai.vesnai.shared` on both the app and the extension.
- The app mirrors the snapshot into `UserDefaults(suiteName:)`; the widget reads
  `widget_snapshot`. Quick-capture uses the `vesnai://capture` deep link.

### Android (Glance, Kotlin)

- Source: `app/android/app/src/main/kotlin/ai/vesnai/vesnai_app/widget/VesnaiGlanceWidget.kt`;
  tests: `app/android/app/src/test/.../WidgetStoreTest.kt`.
- The app writes the snapshot JSON into the `vesnai_widget` shared-prefs file;
  `WidgetStore.parseRecents` reads it. Register `VesnaiGlanceReceiver` in the
  manifest as an `appwidget-provider`.

### Testing

- Dart contract: `app/test/data/shared_storage_test.dart` (round-trip + drain).
- iOS: XCTest (snapshot decode + timeline) on Xcode CI.
- Android: JUnit/Robolectric (`WidgetStoreTest`) on Gradle CI.
- These native tests run on platform CI, not in `flutter test`.
