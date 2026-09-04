import 'package:flutter/material.dart';

import '../features/notes/notes_screen.dart';
export '../features/notes/sticky_note_card.dart';

/// The desktop board shares capture, filters, sync, and layout controls with Notes.
class StickyBoard extends StatelessWidget {
  const StickyBoard({super.key});
  @override
  Widget build(BuildContext context) => const NotesScreen(initialGrid: true);
}
