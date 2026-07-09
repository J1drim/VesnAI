import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'location_context.dart';

/// Reads device location for chat turn context (when user enables the setting).
class ChatLocationService {
  Future<SavedLocation?> resolveForChat({
    required bool shareEnabled,
    SavedLocation? saved,
    DateTime? now,
  }) async {
    if (!shareEnabled) {
      return null;
    }
    final clock = now ?? DateTime.now();
    final decision = locationRefreshDecision(saved: saved, now: clock);
    if (decision == LocationRefreshDecision.reuseSaved && saved != null) {
      return saved;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return saved;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return saved;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: locationGpsTimeout,
        ),
      );
    } catch (_) {
      position = null;
    }

    if (position != null && saved != null) {
      final afterQuickRead = locationRefreshDecision(
        saved: saved,
        now: clock,
        newLat: position.latitude,
        newLon: position.longitude,
        newAccuracyM: position.accuracy,
      );
      if (afterQuickRead == LocationRefreshDecision.reuseSaved) {
        return saved;
      }
    }

    if (position == null) {
      return saved;
    }

    String? label;
    try {
      final places = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (places.isNotEmpty) {
        final p = places.first;
        final parts = [
          if ((p.locality ?? '').isNotEmpty) p.locality,
          if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea,
          if ((p.country ?? '').isNotEmpty) p.country,
        ].whereType<String>().toList();
        if (parts.isNotEmpty) {
          label = parts.join(', ');
        }
      }
    } catch (_) {
      label = null;
    }

    return SavedLocation(
      lat: position.latitude,
      lon: position.longitude,
      label: label,
      accuracyM: position.accuracy,
      capturedAt: clock,
    );
  }
}
