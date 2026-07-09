import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/graph_layout.dart';

void main() {
  test('encodeLayoutWithScale round-trips scale', () {
    const graphJson = '{"nodes":[],"edges":[]}';
    final encoded = encodeLayoutWithScale(graphJson, 1.5);
    expect(parseLayoutScale(encoded), 1.5);
  });

  test('parseLayoutScale defaults to 1.0', () {
    expect(parseLayoutScale(null), 1.0);
    expect(parseLayoutScale('{"nodes":[]}'), 1.0);
  });
}
