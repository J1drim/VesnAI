import 'package:flutter/material.dart';
import 'package:flutter_force_directed_graph/flutter_force_directed_graph.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/graph_layout_store.dart';
import 'package:vesnai_app/features/graph/graph_screen.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/models/note.dart';
import 'package:vesnai_app/providers.dart';
import 'package:vesnai_app/theme.dart';

class _FakeNotes extends NotesNotifier {
  _FakeNotes(this._notes);

  final List<Note> _notes;

  @override
  Future<List<Note>> build() async => _notes;
}

class _DelayedNotes extends NotesNotifier {
  _DelayedNotes(this._notes);

  final List<Note> _notes;

  @override
  Future<List<Note>> build() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return _notes;
  }
}

Note _note(String path, String title, {List<String> tags = const []}) => Note(
      path: path,
      title: title,
      body: 'body',
      tags: tags,
    );

ProviderScope _graphScope(List<Note> notes, Widget child) => ProviderScope(
      overrides: [
        notesProvider.overrideWith(() => _FakeNotes(notes)),
        graphLayoutStoreProvider.overrideWithValue(InMemoryGraphLayoutStore()),
      ],
      child: MaterialApp(
        theme: VesnaiTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

Future<void> _pumpUntilGraphSettled(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('GraphScreen shows node labels without canvas interaction',
      (tester) async {
    final notes = [
      _note('notes/a.md', 'Alpha'),
      _note('notes/b.md', 'Beta'),
      _note('notes/c.md', 'Gamma'),
    ];

    await tester.pumpWidget(_graphScope(notes, const GraphScreen()));
    await _pumpUntilGraphSettled(tester);

    expect(find.byType(ForceDirectedGraphWidget<String>), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('GraphScreen shows nodes after notes load post-mount',
      (tester) async {
    final notes = [
      _note('notes/a.md', 'Alpha'),
      _note('notes/b.md', 'Beta'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesProvider.overrideWith(() => _DelayedNotes(notes)),
          graphLayoutStoreProvider.overrideWithValue(InMemoryGraphLayoutStore()),
        ],
        child: MaterialApp(
          theme: VesnaiTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GraphScreen(),
        ),
      ),
    );
    await _pumpUntilGraphSettled(tester);

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('filter bar uses Tags chip instead of listing every tag',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final notes = [
      _note('notes/a.md', 'Alpha', tags: ['work']),
      _note('notes/b.md', 'Beta', tags: ['home', 'ideas']),
    ];

    await tester.pumpWidget(_graphScope(notes, const GraphScreen()));
    await _pumpUntilGraphSettled(tester);

    expect(find.byKey(const Key('graph-tags-filter')), findsOneWidget);
    expect(find.text('#work'), findsNothing);
    expect(find.text('#home'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);

    final tagsChip = find.byKey(const Key('graph-tags-filter'));
    await tester.scrollUntilVisible(
      tagsChip,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(tagsChip);
    await tester.pumpAndSettle();

    expect(find.text('Filter by tag'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    final workChip = find.byKey(const Key('graph-tag-work'));
    await tester.scrollUntilVisible(
      workChip,
      100,
      scrollable: find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(workChip);
    await tester.pumpAndSettle();

    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('#work'), findsAtLeast(1));
    expect(find.text('Alpha'), findsOneWidget);
    final selected = ProviderScope.containerOf(
      tester.element(find.byType(GraphScreen)),
    ).read(graphFiltersProvider).tags;
    expect(selected, contains('work'));
  });
}
