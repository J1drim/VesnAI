import 'dart:convert';
import 'dart:math' as math;

/// Thresholds for when to refresh GPS (see chat location plan).
const locationRefreshDistanceM = 1000.0;
const locationMinRefreshInterval = Duration(minutes: 5);
const locationMaxAge = Duration(hours: 24);
const locationGpsTimeout = Duration(seconds: 5);

/// Last known position shared with chat when the setting is enabled.
class SavedLocation {
  final double lat;
  final double lon;
  final String? label;
  final double? accuracyM;
  final DateTime capturedAt;

  const SavedLocation({
    required this.lat,
    required this.lon,
    this.label,
    this.accuracyM,
    required this.capturedAt,
  });

  Map<String, dynamic> toApiJson() => {
        'lat': lat,
        'lon': lon,
        if (label != null && label!.isNotEmpty) 'label': label,
        if (accuracyM != null) 'accuracy_m': accuracyM,
        'captured_at': capturedAt.toUtc().toIso8601String(),
      };

  static SavedLocation? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return SavedLocation(
        lat: (map['lat'] as num).toDouble(),
        lon: (map['lon'] as num).toDouble(),
        label: map['label'] as String?,
        accuracyM: map['accuracy_m'] != null
            ? (map['accuracy_m'] as num).toDouble()
            : null,
        capturedAt: DateTime.parse(map['captured_at'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  String toJsonString() => jsonEncode({
        'lat': lat,
        'lon': lon,
        if (label != null) 'label': label,
        if (accuracyM != null) 'accuracy_m': accuracyM,
        'captured_at': capturedAt.toUtc().toIso8601String(),
      });
}

/// Haversine distance in meters between two WGS84 points.
double haversineDistanceM(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusM = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}

double _toRad(double deg) => deg * math.pi / 180.0;

enum LocationRefreshDecision { fetchGps, reuseSaved }

/// Pure policy: should we hit GPS or reuse [saved]?
LocationRefreshDecision locationRefreshDecision({
  required SavedLocation? saved,
  required DateTime now,
  double? newLat,
  double? newLon,
  double? newAccuracyM,
}) {
  if (saved == null) {
    return LocationRefreshDecision.fetchGps;
  }
  if (now.difference(saved.capturedAt) > locationMaxAge) {
    return LocationRefreshDecision.fetchGps;
  }
  if (now.difference(saved.capturedAt) < locationMinRefreshInterval) {
    return LocationRefreshDecision.reuseSaved;
  }
  if (newLat == null || newLon == null) {
    return LocationRefreshDecision.reuseSaved;
  }
  final moved = haversineDistanceM(saved.lat, saved.lon, newLat, newLon);
  final threshold = math.max(
    locationRefreshDistanceM,
    (saved.accuracyM ?? 0) + (newAccuracyM ?? 0),
  );
  if (moved > threshold) {
    return LocationRefreshDecision.fetchGps;
  }
  return LocationRefreshDecision.reuseSaved;
}
