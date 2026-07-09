import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_force_directed_graph/flutter_force_directed_graph.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/graph_layout.dart';
import '../../data/local_graph.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../note_detail/note_detail_screen.dart';
import '../notes/note_preview.dart';
import '../notes/note_type_ui.dart';

class GraphFilters {
  final String? origin;
  final String? type;
  final Set<String> tags;
  final bool showAll;
  const GraphFilters({
    this.origin,
    this.type,
    this.tags = const {},
    this.showAll = false,
  });
  bool get hasActiveFilters =>
      origin != null || type != null || tags.isNotEmpty || showAll;
  GraphFilters copyWith({
    String? origin,
    String? type,
    Set<String>? tags,
    bool? showAll,
    bool clearOrigin = false,
    bool clearType = false,
    bool clearTags = false,
  }) =>
      GraphFilters(
        origin: clearOrigin ? null : (origin ?? this.origin),
        type: clearType ? null : (type ?? this.type),
        tags: clearTags ? const {} : (tags ?? this.tags),
        showAll: showAll ?? this.showAll,
      );
  GraphFilters toggleTag(String tag) {
    final next = Set<String>.from(tags);
    if (next.contains(tag)) {
      next.remove(tag);
    } else {
      next.add(tag);
    }
    return copyWith(tags: next);
  }
}

/// Group tags by first letter (A–Z); non-letter tags go under `#`.
Map<String, List<String>> groupTagsByFirstLetter(Iterable<String> tags) {
  final groups = <String, List<String>>{};
  for (final tag in tags) {
    final first = tag.isNotEmpty ? tag[0].toUpperCase() : '#';
    final letter = first.codeUnitAt(0) >= 65 && first.codeUnitAt(0) <= 90 ? first : '#';
    groups.putIfAbsent(letter, () => []).add(tag);
  }
  for (final list in groups.values) {
    list.sort();
  }
  final keys = groups.keys.toList()..sort();
  return {for (final k in keys) k: groups[k]!};
}

final graphFiltersProvider = StateProvider<GraphFilters>((ref) => const GraphFilters());

/// Knowledge graph derived from the local note mirror (client-only; no server call).
final graphProvider = Provider<Map<String, dynamic>>((ref) {
  final notes = ref.watch(notesProvider).valueOrNull ?? const [];
  final f = ref.watch(graphFiltersProvider);
  final visible = f.showAll ? notes : notes.where(noteVisibleInMainList).toList();
  return buildLocalGraph(
    visible,
    origin: f.origin,
    type: f.type,
    tags: f.tags,
  );
});

/// Metadata for rendering a graph node (label + type + origin).
class _NodeMeta {
  final String label;
  final String type;
  final bool generated;
  const _NodeMeta(this.label, this.type, this.generated);
}

class GraphScreen extends ConsumerStatefulWidget {
  const GraphScreen({super.key});

  @override
  ConsumerState<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends ConsumerState<GraphScreen> {
  ForceDirectedGraphController<String> _controller =
      ForceDirectedGraphController<String>();
  final Map<String, _NodeMeta> _meta = {};
  String _signature = '';
  bool _layoutReady = false;
  bool _rebuildInFlight = false;
  int _canvasKey = 0;
  bool _refreshing = false;
  Timer? _layoutSaveTimer;

  @override
  void initState() {
    super.initState();
    _controller.setOnScaleChange((_) => _scheduleLayoutSave());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_scheduleRebuildIfNeeded(ref.read(graphProvider)));
      }
    });
  }

  @override
  void dispose() {
    _layoutSaveTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  static String _signatureOf(Map<String, dynamic> data) => graphDataSignature(data);

  void _scheduleLayoutSave() {
    _layoutSaveTimer?.cancel();
    _layoutSaveTimer = Timer(const Duration(milliseconds: 500), () {
      final encoded = encodeLayoutWithScale(
        _controller.toJson(),
        _controller.scale,
      );
      unawaited(ref.read(graphLayoutStoreProvider).save(encoded));
    });
  }

  Future<void> _scheduleRebuildIfNeeded(Map<String, dynamic> data) async {
    final nodes = (data['nodes'] as List);
    if (nodes.isEmpty) {
      _signature = _signatureOf(data);
      if (mounted && !_layoutReady) setState(() => _layoutReady = true);
      return;
    }
    if (_rebuildInFlight || _signatureOf(data) == _signature) {
      if (mounted && !_layoutReady && !_rebuildInFlight) {
        setState(() => _layoutReady = true);
      }
      return;
    }
    _rebuildInFlight = true;
    if (mounted) setState(() => _layoutReady = false);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _rebuild(data);
    _rebuildInFlight = false;
    if (mounted) {
      setState(() {
        _layoutReady = true;
        _canvasKey++;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.needUpdate();
      });
    }
  }

  /// Rebuild the controller's nodes/edges when graph data changes.
  Future<void> _rebuild(Map<String, dynamic> data, {bool persist = true}) async {
    final nodes = (data['nodes'] as List).cast<Map>();
    final edges = (data['edges'] as List).cast<Map>();
    final ids = nodes.map((n) => n['id'] as String).toList();
    _signature = _signatureOf(data);

    _meta
      ..clear()
      ..addEntries(nodes.map((n) => MapEntry(
            n['id'] as String,
            _NodeMeta(
              (n['title'] as String?)?.trim().isNotEmpty == true
                  ? n['title'] as String
                  : (n['id'] as String).split('/').last,
              normalizeNoteType(n['type'] as String?),
              n['origin'] == 'generated',
            ),
          )));

    final saved = await ref.read(graphLayoutStoreProvider).load();
    final positions = pruneLayoutPositions(
      data,
      parseLayoutPositions(saved),
    );
    final savedScale = parseLayoutScale(saved);

    final nextController = ForceDirectedGraphController<String>();
    nextController.setOnScaleChange((_) => _scheduleLayoutSave());
    nextController.graph = ForceDirectedGraph<String>();
    final present = ids.toSet();
    final withoutSavedPos = <String>[];
    final nodeById = <String, dynamic>{};
    for (final id in ids) {
      final node = nextController.addNode(id);
      nodeById[id] = node;
      final savedPos = positions[id];
      if (savedPos != null) {
        node.position.setValues(savedPos.x, savedPos.y);
      } else {
        withoutSavedPos.add(id);
      }
    }
    final spread = initialSpreadPositions(withoutSavedPos);
    for (final entry in spread.entries) {
      nodeById[entry.key]?.position.setValues(entry.value.x, entry.value.y);
    }
    final seen = <String>{};
    for (final e in edges) {
      final a = e['source'] as String;
      final b = e['target'] as String;
      if (a == b || !present.contains(a) || !present.contains(b)) continue;
      final key = a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
      if (!seen.add(key)) continue;
      nextController.addEdgeByData(a, b);
    }

    nextController.scale = savedScale;

    if (persist) {
      await ref.read(graphLayoutStoreProvider).save(
            encodeLayoutWithScale(nextController.toJson(), nextController.scale),
          );
    }

    final previous = _controller;
    _controller = nextController;
    previous.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final pushed = await ref.read(notesProvider.notifier).sync();
      if (!mounted) return;
      final data = ref.read(graphProvider);
      await _scheduleRebuildIfNeeded(data);
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pushed < 0 ? l.graphOffline : l.graphRefreshed(pushed)),
      ));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _open(String id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteDetailScreen(path: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesProvider);
    final data = ref.watch(graphProvider);
    final filters = ref.watch(graphFiltersProvider);
    final theme = Theme.of(context);

    ref.listen(graphProvider, (prev, next) {
      unawaited(_scheduleRebuildIfNeeded(next));
    });

    final nodes = (data['nodes'] as List).cast<Map>();
    if (notesAsync.hasValue &&
        nodes.isNotEmpty &&
        !_layoutReady &&
        !_rebuildInFlight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_scheduleRebuildIfNeeded(data));
      });
    }

    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.knowledgeGraph),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              key: const Key('graph-refresh'),
              tooltip: l.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: () => unawaited(_refresh()),
            ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(filters: filters),
          Expanded(
            child: notesAsync.isLoading && !notesAsync.hasValue
                ? const Center(child: CircularProgressIndicator())
                : nodes.isEmpty
                    ? Center(
                        child: Text(
                          filters.hasActiveFilters
                              ? l.graphNoNotesMatchFilters
                              : l.graphNoNotes,
                        ),
                      )
                    : !_layoutReady
                        ? const Center(child: CircularProgressIndicator())
                        : _GraphCanvas(
                            key: ValueKey(_canvasKey),
                            theme: theme,
                            controller: _controller,
                            meta: _meta,
                            onOpen: _open,
                            onLayoutChanged: _scheduleLayoutSave,
                          ),
          ),
        ],
      ),
    );
  }
}

class _GraphCanvas extends StatefulWidget {
  final ThemeData theme;
  final ForceDirectedGraphController<String> controller;
  final Map<String, _NodeMeta> meta;
  final void Function(String id) onOpen;
  final VoidCallback onLayoutChanged;

  const _GraphCanvas({
    super.key,
    required this.theme,
    required this.controller,
    required this.meta,
    required this.onOpen,
    required this.onLayoutChanged,
  });

  @override
  State<_GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends State<_GraphCanvas> {
  @override
  void initState() {
    super.initState();
    _scheduleControllerRefresh();
  }

  @override
  void didUpdateWidget(covariant _GraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _scheduleControllerRefresh();
    }
  }

  void _scheduleControllerRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.needUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).graphSemantics,
      child: ForceDirectedGraphWidget<String>(
        controller: widget.controller,
        onDraggingEnd: (_) => widget.onLayoutChanged(),
        nodesBuilder: (context, id) {
          final nodeMeta = widget.meta[id] ??
              _NodeMeta(id.split('/').last, 'Note', false);
          final style = noteTypeStyle(nodeMeta.type, widget.theme.colorScheme);
          final fill = style.fill;
          final labelColor = noteTypeLabelColor(fill, widget.theme.colorScheme);
          return GestureDetector(
            onTap: () => widget.onOpen(id),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(16),
                border: nodeMeta.generated
                    ? Border.all(color: VesnaiTheme.generatedAccent, width: 1.5)
                    : null,
                boxShadow: const [
                  BoxShadow(blurRadius: 4, color: Colors.black26),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (nodeMeta.generated) ...[
                    Icon(Icons.auto_awesome, size: 12, color: labelColor),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      nodeMeta.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        edgesBuilder: (context, a, b, distance) => Container(
          width: distance,
          height: 1.5,
          color: widget.theme.colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  final GraphFilters filters;
  const _FilterBar({required this.filters});

  Future<void> _openTagsSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder: (_, scrollController) => _GraphTagsSheet(
            scrollController: scrollController,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(graphFiltersProvider.notifier);
    final l = AppLocalizations.of(context);
    final tagCount = filters.tags.length;
    final tagsLabel =
        tagCount == 0 ? l.tagsFilterLabel : l.tagsFilterLabelCount(tagCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              FilterChip(
                label: Text(l.filterMine),
                selected: filters.origin == 'user',
                onSelected: (s) => notifier.state =
                    filters.copyWith(origin: s ? 'user' : null, clearOrigin: !s),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(l.aiGenerated),
                selected: filters.origin == 'generated',
                onSelected: (s) => notifier.state = filters.copyWith(
                  origin: s ? 'generated' : null,
                  clearOrigin: !s,
                ),
              ),
              const SizedBox(width: 16),
              FilterChip(
                label: Text(l.showAll),
                selected: filters.showAll,
                onSelected: (s) => notifier.state = filters.copyWith(showAll: s),
              ),
              const SizedBox(width: 8),
              for (final t in kUserNoteTypes)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: NoteTypeFilterChip(
                    type: t,
                    selected: filters.type == t,
                    onSelected: (s) => notifier.state =
                        filters.copyWith(type: s ? t : null, clearType: !s),
                  ),
                ),
              FilterChip(
                key: const Key('graph-tags-filter'),
                label: Text(tagsLabel),
                selected: tagCount > 0,
                onSelected: (_) => _openTagsSheet(context, ref),
              ),
            ],
          ),
        ),
        if (filters.tags.isNotEmpty || filters.hasActiveFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final tag in filters.tags.toList()..sort())
                  FilterChip(
                    label: Text('#$tag'),
                    selected: true,
                    onSelected: (_) => notifier.state = filters.toggleTag(tag),
                  ),
                if (filters.hasActiveFilters)
                  TextButton(
                    onPressed: () => notifier.state = const GraphFilters(),
                    child: Text(l.clearFilters),
                  ),
              ],
            ),
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }
}

class _GraphTagsSheet extends ConsumerWidget {
  final ScrollController scrollController;
  const _GraphTagsSheet({required this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(graphFiltersProvider);
    final notifier = ref.read(graphFiltersProvider.notifier);
    final knownTags = ref.watch(knownTagsProvider).toList()..sort();
    final selected = filters.tags;
    final unselected = knownTags.where((t) => !selected.contains(t));
    final sections = groupTagsByFirstLetter(unselected);
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(l.filterByTag, style: theme.textTheme.titleMedium),
        ),
        if (selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.selectedLabel, style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final tag in selected.toList()..sort())
                      FilterChip(
                        label: Text('#$tag'),
                        selected: true,
                        onSelected: (_) =>
                            notifier.state = filters.toggleTag(tag),
                      ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: knownTags.isEmpty
              ? Center(
                  child: Text(
                    l.noTagsYet,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  children: [
                    if (sections.isEmpty && selected.isNotEmpty)
                      Text(
                        l.allTagsSelected,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    for (final entry in sections.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.key, style: theme.textTheme.labelLarge),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final tag in entry.value)
                                  FilterChip(
                                    key: Key('graph-tag-$tag'),
                                    label: Text('#$tag'),
                                    selected: false,
                                    onSelected: (_) => notifier.state =
                                        filters.toggleTag(tag),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (selected.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      notifier.state = filters.copyWith(clearTags: true),
                  child: Text(l.clearTags),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.done),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
