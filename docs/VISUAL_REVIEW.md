# Visual evolution review

The app retains its green seed, type palette, generated accent and rounded
cards. Notes and desktop now share capture, sync status, filters and a persisted
list/card switch. Cards are keyboard-activatable; lists and grids build lazily.
Wide windows use a navigation rail. The note reader is capped at 860 logical
pixels and chat bubbles at 760. Settings provides System/Light/Dark appearance.

`app/test/features/visual_layout_test.dart` checks Notes, reader, chat and board
in English/Polish, light/dark, 390/1280-pixel windows, plus 1.8× text scale.
It uses isolated fixture data and never opens the user's stored library.

The images in `docs/screenshots` are widget-rendered review fixtures, not physical
device screenshots. Text uses Roboto and icons use the app's Material icon font.
Chat content is a fixed English sample, including when the surrounding UI is
Polish. Platform-specific window chrome and physical-device accessibility are
not validated by these fixtures.

Regenerate locally with the Flutter SDK's bundled review font:

```sh
flutter test --no-pub --update-goldens \
  --dart-define=VISUAL_FONT=/path/to/flutter/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf \
  test/features/visual_layout_test.dart
```

Normal CI runs the layout/large-text assertions without requiring that SDK source
font. The smaller note-list pixel golden fixes the Material target platform to
Android so host-platform typography doesn't select different baselines.
