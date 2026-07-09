import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/media_volume.dart';
import 'package:vesnai_app/data/volume_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('vesnai/media_volume');
  late PlatformVolumeGate gate;

  setUp(() {
    gate = PlatformVolumeGate();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('canAutoSpeak is false when volume is zero', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getMusicVolume');
      return 0.0;
    });

    expect(await gate.canAutoSpeak(), isFalse);
  });

  test('canAutoSpeak is true when volume is above threshold', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 0.5);

    expect(await gate.canAutoSpeak(), isTrue);
  });

  test('canAutoSpeak fails open on platform exception', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'error');
    });

    expect(await gate.canAutoSpeak(), isTrue);
  });

  test('canAutoSpeak fails open when plugin is missing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    expect(await gate.canAutoSpeak(), isTrue);
  });

  test('getMusicVolume clamps to 0.0–1.0', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 1.5);

    expect(await const MediaVolumeReader().getMusicVolume(), 1.0);
  });
}
