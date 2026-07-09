import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okf_dart/okf_dart.dart';
import 'package:vesnai_app/features/notes/note_tile.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/models/note.dart';
import 'package:vesnai_app/theme.dart';

void main() {
  testWidgets('note list golden (user + generated + pending)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      theme: VesnaiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ListView(
          children: const [
            NoteTile(
              note: Note(
                path: 'notes/idea.md',
                title: 'Trip to see the northern lights',
                body: 'Travel to northern Norway in winter.',
                type: 'Idea',
              ),
            ),
            NoteTile(
              note: Note(
                path: 'generated/idea-image.md',
                title: 'Aurora over Tromso (image)',
                body: 'Generated to help you remember this idea.',
                origin: Origin.generated,
              ),
            ),
            NoteTile(
              note: Note(
                path: 'notes/pending.md',
                title: 'Buy oat milk',
                body: 'remember to buy oat milk',
                syncState: SyncState.pendingCreate,
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final goldenFile = Platform.environment.containsKey('GITHUB_ACTIONS')
        ? 'note_list_linux.png'
        : (Platform.isLinux ? 'note_list_linux.png' : 'note_list.png');

    await expectLater(
      find.byType(ListView),
      matchesGoldenFile(goldenFile),
    );
  });
}
