import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okf_dart/okf_dart.dart';
import 'package:vesnai_app/data/drift/database.dart';
import 'package:vesnai_app/data/local_graph.dart';
import 'package:vesnai_app/data/local_store.dart';
import 'package:vesnai_app/models/note.dart';

/// Opt-in host baseline, not a physical-device/frame-time performance claim.
void main() {
  for (final count in [100, 1000, 10000]) {
    test(
      'library baseline $count notes',
      () async {
        final db = VesnaiDatabase(NativeDatabase.memory());
        final store = DriftNoteStore(db);
        addTearDown(db.close);
        final timer = Stopwatch()..start();
        await store.transaction(() async {
          for (var i = 0; i < count; i++) {
            await store.put(
              Note(
                path: 'notes/$i.md',
                title: 'Creative project $i',
                body: List.filled(
                  10,
                  'A short paragraph about research, reading, creative work and ideas.',
                ).join('\n'),
                tags: ['project-${i % 20}'],
                links: i > 0 ? ['notes/${i - 1}.md'] : [],
              ),
            );
          }
        });
        final insertMs = timer.elapsedMilliseconds;
        final samples = <int>[];
        for (var i = 0; i < 20; i++) {
          timer.reset();
          expect(
            await store.search('creat research', limit: 100),
            hasLength(100),
          );
          samples.add(timer.elapsedMicroseconds);
        }
        samples.sort();
        timer.reset();
        final all = await store.all();
        final catalogMs = timer.elapsedMilliseconds;
        timer.reset();
        final graph = buildLocalGraph(all);
        final graphMs = timer.elapsedMilliseconds;
        expect(graph['nodes'], hasLength(count));
        timer.reset();
        final docs = all.map((n) => dumpConcept(n.toConcept())).toList();
        final serializeMs = timer.elapsedMilliseconds;
        expect(docs, hasLength(count));
        // ignore: avoid_print
        print(
          'BASELINE notes=$count insert_ms=$insertMs search_median_us=${samples[10]} search_p95_us=${samples[18]} catalog_ms=$catalogMs graph_ms=$graphMs serialize_ms=$serializeMs',
        );
      },
      skip: !const bool.fromEnvironment('BENCHMARK_LIBRARY'),
    );
  }
}
