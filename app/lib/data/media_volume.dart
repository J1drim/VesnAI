import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Read-only bridge to native media/music volume (0.0–1.0).
///
/// Used to gate auto-speak when the device is muted. No arguments are passed
/// to native code; only [getMusicVolume] is exposed.
class MediaVolumeReader {
  static const _channel = MethodChannel('vesnai/media_volume');

  const MediaVolumeReader();

  /// Returns normalized media volume, or `null` when unavailable.
  Future<double?> getMusicVolume() async {
    try {
      final vol = await _channel.invokeMethod<double>('getMusicVolume');
      if (vol == null) return null;
      return vol.clamp(0.0, 1.0);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('getMusicVolume failed: $e');
      return null;
    }
  }
}
