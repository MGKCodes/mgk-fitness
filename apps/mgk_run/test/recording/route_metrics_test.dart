import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/recording/domain/route_metrics.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';

RunPoint _p(double lat, double lng, {double accuracy = 5}) => RunPoint(
  latitude: lat,
  longitude: lng,
  accuracyMeters: accuracy,
  timestamp: DateTime(2026, 1, 1),
);

void main() {
  group('haversineMeters', () {
    test('is zero for the same point', () {
      expect(haversineMeters(51.5, -0.1, 51.5, -0.1), 0);
    });

    test('one thousandth of a degree of latitude is ~111.2 m', () {
      // 1 degree on a 6371 km sphere is ~111.195 km, so 0.001 deg ~ 111.2 m.
      expect(haversineMeters(0, 0, 0.001, 0), closeTo(111.19, 0.5));
    });

    test('longitude spacing shrinks with latitude', () {
      final atEquator = haversineMeters(0, 0, 0, 0.001);
      final atFiftyOne = haversineMeters(51, 0, 51, 0.001);
      expect(atFiftyOne, lessThan(atEquator));
      // cos(51°) ~ 0.629, so it should be roughly 63% of the equatorial span.
      expect(atFiftyOne, closeTo(atEquator * 0.629, 1));
    });
  });

  group('routeDistanceMeters', () {
    test('sums consecutive segments of a clean trace', () {
      final points = [_p(0, 0), _p(0, 0.001), _p(0, 0.002)];
      expect(routeDistanceMeters(points), closeTo(222.39, 1));
    });

    test('is zero for fewer than two usable points', () {
      expect(routeDistanceMeters([_p(0, 0)]), 0);
      expect(routeDistanceMeters(const <RunPoint>[]), 0);
    });

    test('discards poor-accuracy fixes instead of jumping to them', () {
      final clean = [_p(0, 0), _p(0, 0.001), _p(0, 0.002)];
      final withWildFix = [
        _p(0, 0),
        _p(0, 0.001),
        _p(0, 0.5, accuracy: 100), // a wild, low-accuracy jump
        _p(0, 0.002),
      ];
      // The bad fix is skipped, so distance matches the clean trace.
      expect(
        routeDistanceMeters(withWildFix),
        closeTo(routeDistanceMeters(clean), 0.001),
      );
    });

    test('accuracy threshold is configurable', () {
      final points = [_p(0, 0, accuracy: 30), _p(0, 0.001, accuracy: 30)];
      // Both fixes are dropped at the default 20 m threshold...
      expect(routeDistanceMeters(points), 0);
      // ...but kept when the threshold is relaxed.
      expect(routeDistanceMeters(points, maxAccuracyM: 50), closeTo(111.19, 1));
    });
  });

  group('processedDistanceMeters', () {
    test('matches the raw distance for a clean moving trace', () {
      final points = [_p(0, 0), _p(0, 0.001), _p(0, 0.002)];
      expect(processedDistanceMeters(points), closeTo(222.39, 1));
    });

    test('ignores sub-metre jitter while stationary', () {
      // Four fixes all within ~0.7 m of the origin (standing still).
      final jitter = [
        _p(0, 0),
        _p(0, 0.000005),
        _p(0, 0.000003),
        _p(0, 0.000006),
      ];
      expect(processedDistanceMeters(jitter), lessThan(1));
    });

    test('counts real movement either side of a stationary blip', () {
      final points = [
        _p(0, 0),
        _p(0, 0.001), // ~111 m of movement
        _p(0, 0.001005), // ~0.5 m jitter — ignored
        _p(0, 0.002), // ~111 m of movement
      ];
      expect(processedDistanceMeters(points), closeTo(222.39, 1));
    });
  });
}
