import 'media_volume.dart';

/// Whether media volume is high enough to auto-play TTS.
abstract class VolumeGate {
  Future<bool> canAutoSpeak();
}

class PlatformVolumeGate implements VolumeGate {
  final MediaVolumeReader _reader;

  PlatformVolumeGate({MediaVolumeReader? reader})
      : _reader = reader ?? const MediaVolumeReader();

  @override
  Future<bool> canAutoSpeak() async {
    try {
      final vol = await _reader.getMusicVolume();
      if (vol == null) return true;
      return vol > 0.01;
    } catch (_) {
      return true;
    }
  }
}

class AlwaysSpeakVolumeGate implements VolumeGate {
  @override
  Future<bool> canAutoSpeak() async => true;
}

class NeverSpeakVolumeGate implements VolumeGate {
  @override
  Future<bool> canAutoSpeak() async => false;
}
