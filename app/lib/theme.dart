import 'package:flutter/material.dart';

/// VesnAI visual identity: spring/renewal greens with a warm accent.
class VesnaiTheme {
  static const seed = Color(0xFF2E7D5B);
  static const generatedAccent = Color(0xFF8E6BD6);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }
}

/// Spring palette anchored on Capture FAB mint; distinct hues at matched saturation.
class VesnaiTypePalette {
  VesnaiTypePalette._();

  static const ideaIcon = Color(0xFFC9920E);
  static const ideaFill = Color(0xFFF0D78C);
  static const taskIcon = Color(0xFF1F9689);
  static const taskFill = Color(0xFF8ED9CF);
  static const photoIcon = Color(0xFF7B52B8);
  static const photoFill = Color(0xFFD4C0EF);
  // Marena's critiques: a warning red, unmistakably "the enemy of Vesna".
  static const critiqueIcon = Color(0xFFB3342E);
  static const critiqueFill = Color(0xFFEFB0AC);

  static const ideaIconHex = '#FFC9920E';
  static const ideaFillHex = '#FFF0D78C';
  static const taskIconHex = '#FF1F9689';
  static const taskFillHex = '#FF8ED9CF';
  static const photoIconHex = '#FF7B52B8';
  static const photoFillHex = '#FFD4C0EF';

  static Color noteFill(ColorScheme scheme) => scheme.primaryContainer;
  static Color noteIcon(ColorScheme scheme) => scheme.onPrimaryContainer;

  /// Maps internal OKF types to a user-facing palette bucket.
  static String bucket(String type) {
    switch (type) {
      case 'Idea':
      case 'Task':
      case 'Photo':
      case 'Note':
      case 'Critique':
        return type;
      case 'Research':
        return 'Idea';
      case 'GeneratedImage':
      case 'GeneratedCaption':
        return 'Photo';
      case 'Memory':
        return 'Task';
      default:
        return 'Note';
    }
  }
}

/// Material 3 light tokens shared with the Android home-screen widget.
class VesnaiWidgetPalette {
  VesnaiWidgetPalette._();

  static final ColorScheme _light = ColorScheme.fromSeed(
    seedColor: VesnaiTheme.seed,
    brightness: Brightness.light,
  );

  static Color get surface => _light.surface;
  static Color get onSurface => _light.onSurface;
  static Color get onSurfaceVariant => _light.onSurfaceVariant;
  static Color get primary => _light.primary;
  static Color get onPrimary => _light.onPrimary;
  static Color get primaryContainer => _light.primaryContainer;
  static Color get onPrimaryContainer => _light.onPrimaryContainer;
  static Color get surfaceContainerLow => _light.surfaceContainerLow;

  static Color get generatedAccent => VesnaiTheme.generatedAccent;
  static Color get generatedTint =>
      VesnaiTheme.generatedAccent.withValues(alpha: 0.18);

  static Color typeFill(String type) {
    switch (VesnaiTypePalette.bucket(type)) {
      case 'Idea':
        return VesnaiTypePalette.ideaFill;
      case 'Task':
        return VesnaiTypePalette.taskFill;
      case 'Photo':
        return VesnaiTypePalette.photoFill;
      default:
        return _light.primaryContainer;
    }
  }

  static Color typeIcon(String type) {
    switch (VesnaiTypePalette.bucket(type)) {
      case 'Idea':
        return VesnaiTypePalette.ideaIcon;
      case 'Task':
        return VesnaiTypePalette.taskIcon;
      case 'Photo':
        return VesnaiTypePalette.photoIcon;
      default:
        return _light.onPrimaryContainer;
    }
  }

  static Color typeColor(String type, {ColorScheme? scheme}) => typeIcon(type);

  static String typeColorHex(String type) {
    switch (VesnaiTypePalette.bucket(type)) {
      case 'Idea':
        return VesnaiTypePalette.ideaIconHex;
      case 'Task':
        return VesnaiTypePalette.taskIconHex;
      case 'Photo':
        return VesnaiTypePalette.photoIconHex;
      default:
        return hexArgb(_light.onPrimaryContainer);
    }
  }

  static String typeFillHex(String type) {
    switch (VesnaiTypePalette.bucket(type)) {
      case 'Idea':
        return VesnaiTypePalette.ideaFillHex;
      case 'Task':
        return VesnaiTypePalette.taskFillHex;
      case 'Photo':
        return VesnaiTypePalette.photoFillHex;
      default:
        return hexArgb(_light.primaryContainer);
    }
  }

  static String typeTintHex(String type) {
    return hexArgb(typeFill(type).withValues(alpha: 0.18));
  }

  /// `#AARRGGBB` for Android `colors.xml` / Kotlin (ARGB uppercase).
  static String hexArgb(Color color) {
    final v = color.toARGB32();
    return '#${v.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }
}
