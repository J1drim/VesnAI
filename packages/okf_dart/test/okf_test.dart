import 'dart:io';

import 'package:okf_dart/okf_dart.dart';
import 'package:test/test.dart';

void main() {
  group('parse/serialize', () {
    test('basic parse', () {
      final c = parseConcept('---\ntype: Note\ntitle: Hello\n---\nbody\n');
      expect(c.type, 'Note');
      expect(c.title, 'Hello');
      expect(c.body, 'body\n');
    });

    test('missing frontmatter throws', () {
      expect(() => parseConcept('no frontmatter'),
          throwsA(isA<OkfParseException>()));
    });

    test('unclosed frontmatter throws', () {
      expect(() => parseConcept('---\ntype: Note\nno closing'),
          throwsA(isA<OkfParseException>()));
    });

    test('crlf + bom tolerated', () {
      final c = parseConcept('\uFEFF---\r\ntype: Note\r\n---\r\nbody\r\n');
      expect(c.type, 'Note');
    });

    test('round-trip identity preserves frontmatter and body', () {
      final c = Concept(
        frontmatter: {
          'type': 'Idea',
          'title': 'A title',
          'tags': ['idea', 'travel'],
          'vesnai': {'origin': 'user', 'version': 1},
        },
        body: 'some body\nwith lines',
      );
      final once = parseConcept(dumpConcept(c));
      final twice = parseConcept(dumpConcept(once));
      expect(once.frontmatter, twice.frontmatter);
      expect(once.body, twice.body);
      expect(once.tags, ['idea', 'travel']);
      expect(once.origin, Origin.user);
    });

    test('unknown fields preserved', () {
      final c = parseConcept('---\ntype: Note\nweird: 42\n---\nx');
      expect(c.frontmatter['weird'], 42);
      final round = parseConcept(dumpConcept(c));
      expect(round.frontmatter['weird'], 42);
    });
  });

  group('conformance', () {
    test('missing type is error', () {
      final c = parseConcept('---\ntitle: no type\n---\nx');
      final issues = checkConcept('notes/foo.md', c);
      expect(issues.any((i) => i.severity == Severity.error), isTrue);
    });

    test('reserved files need no type', () {
      final c = parseConcept('---\n{}\n---\n# Index\n');
      expect(checkConcept('index.md', c).any((i) => i.severity == Severity.error),
          isFalse);
    });

    test('broken link is warning not error', () {
      final a = Concept(
          frontmatter: {'type': 'Note', 'title': 'A'}, body: '[x](missing.md)');
      final issues = checkBundle({'a.md': a});
      expect(issues.any((i) => i.message.contains('broken cross-link')), isTrue);
      expect(
          issues
              .where((i) => i.message.contains('broken'))
              .every((i) => i.severity == Severity.warning),
          isTrue);
    });
  });

  group('shared cross-language fixtures', () {
    // Resolve fixtures relative to the repo root (../../fixtures/okf).
    final fixturesDir = Directory('../../fixtures/okf');

    test('valid bundle passes (no errors)', () {
      final validDir = Directory('${fixturesDir.path}/valid');
      final concepts = <String, Concept>{};
      for (final entity in validDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.md')) {
          final rel = entity.path
              .substring(validDir.path.length + 1)
              .replaceAll('\\', '/');
          concepts[rel] = parseConcept(entity.readAsStringSync());
        }
      }
      expect(concepts.isNotEmpty, isTrue);
      final issues = checkBundle(concepts);
      expect(issues.where((i) => i.severity == Severity.error), isEmpty,
          reason: issues.toString());
    });

    test('invalid fixture has an error', () {
      final f = File('${fixturesDir.path}/invalid/missing-type.md');
      final c = parseConcept(f.readAsStringSync());
      final issues = checkConcept('invalid/missing-type.md', c);
      expect(issues.any((i) => i.severity == Severity.error), isTrue);
    });
  });
}
