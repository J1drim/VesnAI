import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:vesnai_app/data/attachment_cache.dart';

void main() {
  late Directory tempDir;
  late AttachmentCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('attachment_cache_test');
    cache = AttachmentCache(tempDir);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('write and readBytes round-trip', () async {
    const rel = 'attachments/pic.png';
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await cache.write(rel, bytes);
    expect(await cache.exists(rel), isTrue);
    expect(await cache.readBytes(rel), bytes);
  });

  test('rejects path traversal', () {
    expect(() => cache.localFile('../etc/passwd'), throwsArgumentError);
  });

  test('getOrFetch uses disk on second call', () async {
    const rel = 'attachments/cached.png';
    var fetchCount = 0;
    Future<Uint8List?> fetch() async {
      fetchCount++;
      return Uint8List.fromList([9, 8, 7]);
    }

    final first = await cache.getOrFetch(rel, fetch);
    final second = await cache.getOrFetch(rel, fetch);

    expect(first, isNotNull);
    expect(second, first);
    expect(fetchCount, 1);
    expect(await cache.localFile(rel).exists(), isTrue);
  });
}
