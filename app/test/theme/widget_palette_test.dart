import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/features/notes/note_type_ui.dart';
import 'package:vesnai_app/theme.dart';

void main() {
  test('widget palette matches ColorScheme.fromSeed light scheme', () {
    final scheme = ColorScheme.fromSeed(
      seedColor: VesnaiTheme.seed,
      brightness: Brightness.light,
    );
    expect(VesnaiWidgetPalette.surface, scheme.surface);
    expect(VesnaiWidgetPalette.onSurface, scheme.onSurface);
    expect(VesnaiWidgetPalette.onSurfaceVariant, scheme.onSurfaceVariant);
    expect(VesnaiWidgetPalette.primary, scheme.primary);
    expect(VesnaiWidgetPalette.onPrimary, scheme.onPrimary);
    expect(VesnaiWidgetPalette.primaryContainer, scheme.primaryContainer);
    expect(VesnaiWidgetPalette.onPrimaryContainer, scheme.onPrimaryContainer);
    expect(VesnaiWidgetPalette.surfaceContainerLow, scheme.surfaceContainerLow);
    expect(
      VesnaiWidgetPalette.generatedTint,
      VesnaiTheme.generatedAccent.withValues(alpha: 0.18),
    );
    expect(VesnaiWidgetPalette.typeColor('Idea'), VesnaiTypePalette.ideaIcon);
    expect(VesnaiWidgetPalette.typeColor('Task'), VesnaiTypePalette.taskIcon);
    expect(VesnaiWidgetPalette.typeColor('Photo'), VesnaiTypePalette.photoIcon);
    expect(VesnaiWidgetPalette.typeColorHex('Idea'), VesnaiTypePalette.ideaIconHex);
    expect(VesnaiWidgetPalette.typeFill('Note'), scheme.primaryContainer);
    expect(VesnaiWidgetPalette.typeFill('Research'), VesnaiTypePalette.ideaFill);
  });

  test('normalizeNoteType treats empty as Note', () {
    expect(normalizeNoteType(null), 'Note');
    expect(normalizeNoteType(''), 'Note');
    expect(normalizeNoteType('  '), 'Note');
    expect(normalizeNoteType('Idea'), 'Idea');
  });

  test('noteTypeStyle uses mint fill for Note type', () {
    final scheme = ColorScheme.fromSeed(seedColor: VesnaiTheme.seed);
    final style = noteTypeStyle('Note', scheme);
    expect(style.fill, scheme.primaryContainer);
    expect(style.color, scheme.onPrimaryContainer);
  });
}
