import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/recording/domain/route_metrics.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';

final _start = DateTime(2026, 1, 1, 8);

RunPoint _p(
  double lat,
  double lng, {
  double accuracy = 5,
  Duration at = Duration.zero,
}) => RunPoint(
  latitude: lat,
  longitude: lng,
  accuracyMeters: accuracy,
  timestamp: _start.add(at),
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

    test('does not bridge a gap in the trace', () {
      // A pause, or a lost signal: the recorder stopped persisting, so the
      // trace has a hole. The straight line across it is a line nobody ran.
      final points = [
        _p(0, 0, at: Duration.zero),
        _p(0, 0.001, at: const Duration(seconds: 30)),
        // ...ten minutes and a kilometre later.
        _p(0, 0.01, at: const Duration(minutes: 10)),
        _p(0, 0.011, at: const Duration(minutes: 10, seconds: 30)),
      ];
      // Two segments of ~111 m, and nothing for the ~1 km hole.
      expect(processedDistanceMeters(points), closeTo(222.39, 1));
    });

    test('a normal fix interval is never treated as a gap', () {
      final points = <RunPoint>[
        for (var i = 0; i < 10; i++)
          _p(0, i * 0.001, at: Duration(seconds: i * 3)),
      ];
      expect(processedDistanceMeters(points), closeTo(111.19 * 9, 2));
    });
  });

  group('traceSegments', () {
    test('a clean trace is one segment', () {
      final points = [
        _p(0, 0),
        _p(0, 0.001, at: const Duration(seconds: 3)),
        _p(0, 0.002, at: const Duration(seconds: 6)),
      ];
      final segments = traceSegments(points);
      expect(segments, hasLength(1));
      expect(segments.single, hasLength(3));
    });

    test('splits where recording stopped, so the map does not draw across', () {
      final points = [
        _p(0, 0),
        _p(0, 0.001, at: const Duration(seconds: 3)),
        _p(0, 0.01, at: const Duration(minutes: 10)),
      ];
      final segments = traceSegments(points);
      expect(segments, hasLength(2));
      expect(segments[0], hasLength(2));
      expect(segments[1], hasLength(1));
    });

    test('drops poor fixes before deciding where the breaks are', () {
      final points = [
        _p(0, 0),
        _p(0, 0.5, accuracy: 100, at: const Duration(seconds: 3)),
        _p(0, 0.001, at: const Duration(seconds: 6)),
      ];
      // The wild fix never existed, so this is one continuous segment of two.
      final segments = traceSegments(points);
      expect(segments, hasLength(1));
      expect(segments.single, hasLength(2));
    });

    test('is empty for a trace with nothing usable in it', () {
      expect(traceSegments(const <RunPoint>[]), isEmpty);
      expect(traceSegments([_p(0, 0, accuracy: 100)]), isEmpty);
    });
  });

  // The pair Strava carried for the same 10 km — 167 m of gain, a 111 m high
  // point — and this app carried neither. They are two different questions and
  // the tests here are mostly about keeping them from being answered as one.
  group('climbMeters', () {
    test('sums the rises and ignores the descents', () {
      // Up 30, down 30, up 20: 50 m of climbing, back nearly where it started.
      final climb = climbMeters(<RunPoint>[
        _alt(10),
        _alt(40),
        _alt(10),
        _alt(30),
      ]);
      expect(climb, closeTo(50, 0.001));
    });

    test('a barometer drifting while somebody stands still is not a hill', () {
      // Sub-metre wobble, repeated. Unfiltered this sums into a climb; the
      // noise floor is what stops a coffee stop reading as a stairwell.
      final climb = climbMeters(<RunPoint>[
        for (var i = 0; i < 60; i++) _alt(i.isEven ? 20.0 : 20.6),
      ]);
      expect(climb, isNull);
    });

    test('a flat run reports nothing rather than 0 m', () {
      // True, useless, and it trains the eye to skip the block on the runs
      // where the figure does say something.
      expect(climbMeters(<RunPoint>[_alt(20), _alt(21), _alt(20)]), isNull);
    });

    test('a trace with no altitude at all is absent, not zero', () {
      // Every run this app currently records: no barometric source, so no
      // altitude on any point (ADR-0024).
      expect(climbMeters(<RunPoint>[_p(0, 0), _p(0, 0.001)]), isNull);
      expect(climbMeters(const <RunPoint>[]), isNull);
    });
  });

  group('maxElevationMeters', () {
    test('is the high point of the route, not the sum of its climbs', () {
      // Hill repeats: 90 m of gain over a maximum of 40. Reporting either
      // number for the other would be wrong by a factor of two here and by a
      // factor of ten on a real hill session.
      final points = <RunPoint>[
        _alt(10),
        _alt(40),
        _alt(10),
        _alt(40),
        _alt(10),
        _alt(40),
      ];
      expect(maxElevationMeters(points), 40);
      expect(climbMeters(points), closeTo(90, 0.001));
    });

    test('has no floor, because a low high point is still an answer', () {
      // Sea-level running is not missing data. This is the case where the
      // climb floor would have been exactly the wrong rule to copy.
      expect(maxElevationMeters(<RunPoint>[_alt(2), _alt(4), _alt(3)]), 4);
    });

    test('reads through the points that carry no altitude', () {
      final points = <RunPoint>[_p(0, 0), _alt(35), _p(0, 0.001), _alt(12)];
      expect(maxElevationMeters(points), 35);
    });

    test('a trace with no altitude at all is absent, not zero', () {
      expect(maxElevationMeters(<RunPoint>[_p(0, 0), _p(0, 0.001)]), isNull);
      expect(maxElevationMeters(const <RunPoint>[]), isNull);
    });

    test('a flat run has a maximum even though it has no gain', () {
      // The two absences mean different things and this is the case that
      // separates them: null gain beside a real maximum is a flat run, both
      // null is a phone with no barometer.
      final points = <RunPoint>[_alt(18), _alt(18.2), _alt(18)];
      expect(climbMeters(points), isNull);
      expect(maxElevationMeters(points), 18.2);
    });
  });
}

/// A fix carrying barometric altitude. Position is irrelevant to both elevation
/// functions, so it stays fixed and the metres are the only variable.
RunPoint _alt(double metres) => RunPoint(
  latitude: 0,
  longitude: 0,
  accuracyMeters: 5,
  altitudeMeters: metres,
  timestamp: _start,
);
