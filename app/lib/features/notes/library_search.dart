import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/note_filter.dart';
import '../../models/note.dart';
import '../../providers.dart';

/// The JSON key is value-stable across rebuilds and includes pagination/filter state.
final librarySearchProvider = FutureProvider.autoDispose
    .family<List<Note>, String>((ref, encoded) async {
      await ref.watch(notesProvider.future);
      final q = jsonDecode(encoded) as Map;
      return ref
          .read(localStoreProvider)
          .search(
            q['query'] as String,
            limit: q['limit'] as int,
            filter: NoteFilter(
              scope: q['scope'] as String,
              libraryOnly: true,
              tag: q['tag'] as String,
              sort: q['sort'] as String,
              showDone: q['done'] as bool,
              types: (q['types'] as List).cast<String>().toSet(),
            ),
          );
    });
