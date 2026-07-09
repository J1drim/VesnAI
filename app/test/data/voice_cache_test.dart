import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/voice_cache.dart';

void main() {
  test('ttsContentHash is stable and differs for different content', () {
    expect(ttsContentHash('hello world'), ttsContentHash('hello world'));
    expect(ttsContentHash('hello world'), isNot(ttsContentHash('goodbye world')));
  });

  test('write and existingPath use content hash in filename', () async {
    final root = Directory.systemTemp.createTempSync('voice_cache_test');
    final cache = VoiceCache(root);
    const id = 'msg-abc';
    const text = 'Reply text for TTS';
    final hash = ttsContentHash(text);

    final path = await cache.write(id, hash, Uint8List.fromList([1, 2, 3]), 'wav');
    expect(path, contains('msg-abc_$hash.wav'));

    expect(await cache.existingPath(id, hash), isNotNull);
    expect(await cache.existingPath(id, ttsContentHash('other text')), isNull);
  });

  test('ttsPathMatchesContent matches hashed filenames', () {
    const content = 'hello';
    final hash = ttsContentHash(content);
    expect(ttsPathMatchesContent('/tmp/msg_$hash.wav', content), isTrue);
    expect(ttsPathMatchesContent('/tmp/msg_legacy.wav', content), isFalse);
  });

  test('deleteStaleForMessage removes old hash files', () async {
    final root = Directory.systemTemp.createTempSync('voice_cache_stale');
    final cache = VoiceCache(root);
    const id = 'msg1';
    final oldHash = ttsContentHash('old');
    final newHash = ttsContentHash('new');

    await cache.write(id, oldHash, Uint8List.fromList([1]), 'wav');
    await cache.write(id, newHash, Uint8List.fromList([2]), 'wav');

    expect(await cache.existingPath(id, oldHash), isNull);
    expect(await cache.existingPath(id, newHash), isNotNull);
  });
}
