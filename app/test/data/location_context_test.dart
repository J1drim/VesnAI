import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/location_context.dart';

void main() {
  test('haversineDistanceM is zero for same point', () {
    expect(haversineDistanceM(52.0, 21.0, 52.0, 21.0), 0.0);
  });

  test('locationRefreshDecision fetches when no saved location', () {
    expect(
      locationRefreshDecision(saved: null, now: DateTime(2026, 6, 30)),
      LocationRefreshDecision.fetchGps,
    );
  });

  test('locationRefreshDecision reuses within min interval', () {
    final saved = SavedLocation(
      lat: 52.0,
      lon: 21.0,
      capturedAt: DateTime(2026, 6, 30, 12, 0),
    );
    expect(
      locationRefreshDecision(
        saved: saved,
        now: saved.capturedAt.add(const Duration(minutes: 2)),
        newLat: 52.01,
        newLon: 21.01,
      ),
      LocationRefreshDecision.reuseSaved,
    );
  });

  test('locationRefreshDecision fetches after move beyond threshold', () {
    final saved = SavedLocation(
      lat: 52.0,
      lon: 21.0,
      capturedAt: DateTime(2026, 6, 30, 12, 0),
    );
    expect(
      locationRefreshDecision(
        saved: saved,
        now: saved.capturedAt.add(const Duration(minutes: 10)),
        newLat: 52.02,
        newLon: 21.02,
      ),
      LocationRefreshDecision.fetchGps,
    );
  });

  test('SavedLocation round-trips JSON', () {
    final loc = SavedLocation(
      lat: 50.06,
      lon: 19.94,
      label: 'Kraków',
      accuracyM: 80,
      capturedAt: DateTime.utc(2026, 6, 30, 10, 0),
    );
    final restored = SavedLocation.fromJsonString(loc.toJsonString());
    expect(restored?.lat, loc.lat);
    expect(restored?.label, loc.label);
  });
}
