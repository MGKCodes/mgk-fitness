import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/recording/domain/live_metrics.dart';
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

/// A straight northward run at a steady pace, one fix a second.
///
/// 0.001 degrees of latitude is ~111.19 m, so a metres-per-second speed maps to
/// a latitude step of `speed / 111190`.
List<RunPoint> _steady({
  required double metresPerSecond,
  required int seconds,
  double accuracy = 5,
  Duration from = Duration.zero,
}) => <RunPoint>[
  for (var i = 0; i <= seconds; i++)
    _p(
      i * metresPerSecond / 111190,
      0,
      accuracy: accuracy,
      at: from + Duration(seconds: i),
    ),
];

void main() {
  group('gpsSignalFor', () {
    test('no fix is none, and none does not measure', () {
      expect(gpsSignalFor(null, sinceFix: null), GpsSignal.none);
      expect(GpsSignal.none.measures, isFalse);
    });

    test('a fix too loose to measure with is weak', () {
      // Recorded and drawn, but outside the distance gate — the state the old
      // single-threshold code threw away entirely.
      expect(
        gpsSignalFor(_p(0, 0, accuracy: 35), sinceFix: Duration.zero),
        GpsSignal.weak,
      );
      expect(GpsSignal.weak.measures, isFalse);
    });

    test('an open sky is good, and a loose-but-usable fix is fair', () {
      expect(
        gpsSignalFor(_p(0, 0, accuracy: 5), sinceFix: Duration.zero),
        GpsSignal.good,
      );
      expect(
        gpsSignalFor(_p(0, 0, accuracy: 15), sinceFix: Duration.zero),
        GpsSignal.fair,
      );
      expect(GpsSignal.fair.measures, isTrue);
    });

    test('a stale fix reports no signal however clean it was', () {
      // The defect this argument exists for: strength was read off accuracy
      // alone, so a fix taken under an open sky went on reporting three bars
      // for as long as the runner looked at it -- while the distance behind it
      // had stopped moving and nothing had errored.
      final pristine = _p(0, 0, accuracy: 3);
      expect(gpsSignalFor(pristine, sinceFix: Duration.zero), GpsSignal.good);
      expect(
        gpsSignalFor(pristine, sinceFix: kStaleFixAfter),
        GpsSignal.none,
        reason: 'the threshold itself is stale, not merely past it',
      );
      expect(
        gpsSignalFor(pristine, sinceFix: const Duration(minutes: 5)),
        GpsSignal.none,
      );
    });

    test('a gap shorter than the threshold is not a lost signal', () {
      // Phones lose a few seconds switching between cell and GPS positioning.
      // Calling that "no signal" would cry wolf on every run.
      expect(
        gpsSignalFor(
          _p(0, 0, accuracy: 5),
          sinceFix: kStaleFixAfter - const Duration(seconds: 1),
        ),
        GpsSignal.good,
      );
    });
  });

  group('rollingPace', () {
    test('reports the recent pace, not the average of the whole run', () {
      // Three minutes crawling, then thirty seconds at 3.33 m/s (5:00/km). A
      // cumulative average would still read slow; the runner wants to know
      // what they are doing now.
      final points = <RunPoint>[
        ..._steady(metresPerSecond: 0.5, seconds: 180),
        ..._steady(
          metresPerSecond: 3.33,
          seconds: 30,
          from: const Duration(seconds: 181),
        ),
      ];
      final pace = rollingPace(points);

      expect(pace, isNotNull);
      // ~300 s/km, well clear of the ~2000 s/km the whole run averages.
      expect(pace!.secondsPerKilometer, closeTo(300, 25));
    });

    test('is null before there is enough movement to mean anything', () {
      // Standing at the start line: a real answer, and better than a number.
      expect(rollingPace(_steady(metresPerSecond: 0.1, seconds: 30)), isNull);
      expect(rollingPace(<RunPoint>[_p(0, 0)]), isNull);
      expect(rollingPace(const <RunPoint>[]), isNull);
    });

    test('ignores fixes too loose to measure with', () {
      final points = _steady(
        metresPerSecond: 3.33,
        seconds: 30,
        accuracy: 35, // recordable, not measurable
      );
      expect(rollingPace(points), isNull);
    });
  });

  group('splitsFor', () {
    test('cuts a steady run into even splits', () {
      // 5 m/s for 500 s = 2500 m: two full kilometres and a 500 m remainder.
      final points = _steady(metresPerSecond: 5, seconds: 500);
      final splits = splitsFor(points);

      expect(splits, hasLength(3));
      expect(splits[0].distanceMeters, 1000);
      expect(splits[0].duration.inSeconds, closeTo(200, 2));
      expect(splits[1].index, 2);
      expect(splits[1].duration.inSeconds, closeTo(200, 2));
      // The trailing partial is kept and is honestly short.
      expect(splits[2].distanceMeters, closeTo(500, 15));
    });

    test('interpolates the crossing rather than rounding to a whole fix', () {
      // 3 m/s means a kilometre lands at 333.3 s, between two fixes. Rounding
      // to the nearest fix costs up to a second per split, which is visible
      // over a long run.
      final points = _steady(metresPerSecond: 3, seconds: 400);
      final splits = splitsFor(points);

      expect(splits.first.duration.inMilliseconds, closeTo(333333, 1500));
    });

    test('the partial split can be left out', () {
      final points = _steady(metresPerSecond: 5, seconds: 500);
      expect(splitsFor(points, includePartial: false), hasLength(2));
    });

    test('does not charge a pause to the split it happened in', () {
      // 800 m, ten minutes of nothing, then 400 m. The kilometre completes 200
      // m into the second stretch, and it must not be a twelve-minute
      // kilometre — the runner was standing still for most of that.
      final points = <RunPoint>[
        ..._steady(metresPerSecond: 4, seconds: 200), // 800 m in 200 s
        ..._steady(
          metresPerSecond: 4,
          seconds: 100,
          from: const Duration(minutes: 10, seconds: 200),
        ),
      ];
      final splits = splitsFor(points);

      expect(splits.first.distanceMeters, 1000);
      // 1000 m at 4 m/s is 250 s. The pause is excluded, so this stays near it.
      expect(splits.first.duration.inSeconds, closeTo(250, 8));
    });

    test('an empty or stationary trace produces no splits', () {
      expect(splitsFor(const <RunPoint>[]), isEmpty);
      expect(splitsFor(<RunPoint>[_p(0, 0)]), isEmpty);
    });
  });

  group('the markers and the splits come from one walk', () {
    // The pins on a finished run's map and the rows under it are two views of
    // the same crossings. Walking the trace twice would be a bug with a delay
    // on it — the day the jitter or gap rule moved in one walk and not the
    // other, kilometre three's pin would sit somewhere its row said it did not.

    test('one marker per whole split, and none for the partial', () {
      // 2500 m: two whole kilometres and a 500 m remainder.
      final points = _steady(metresPerSecond: 5, seconds: 500);
      final walk = splitRun(points);

      expect(walk.splits, hasLength(3));
      expect(
        walk.markers,
        hasLength(2),
        reason: 'a partial split closes nothing, so there is nowhere to pin it',
      );
      expect(walk.markers.map((m) => m.index), <int>[1, 2]);
      expect(splitMarkersFor(points), hasLength(2));
    });

    test('a marker carries the time the runner crossed it', () {
      // 5 m/s, so the first kilometre lands at 200 s and the second at 400 s.
      final walk = splitRun(_steady(metresPerSecond: 5, seconds: 500));

      expect(
        walk.markers.first.at.difference(_start).inSeconds,
        closeTo(200, 2),
      );
      expect(
        walk.markers.last.at.difference(_start).inSeconds,
        closeTo(400, 2),
      );
    });

    test('and the run clock at the crossing, not the wall clock', () {
      // The distinction only shows up across a gap. 800 m, ten minutes of
      // nothing, then 400 m: the kilometre turns over 200 m into the second
      // stretch, at a wall-clock time twelve minutes after the start and a
      // running time of about 250 s. A pin claiming twelve minutes would
      // contradict the split row printed beside it.
      final points = <RunPoint>[
        ..._steady(metresPerSecond: 4, seconds: 200),
        ..._steady(
          metresPerSecond: 4,
          seconds: 100,
          from: const Duration(minutes: 10, seconds: 200),
        ),
      ];
      final marker = splitRun(points).markers.single;

      expect(marker.elapsed.inSeconds, closeTo(250, 8));
      expect(
        marker.at.difference(_start).inSeconds,
        greaterThan(600),
        reason: 'the wall clock did keep running — that is the point',
      );
    });

    test('elapsed accumulates across splits', () {
      final walk = splitRun(_steady(metresPerSecond: 5, seconds: 500));

      expect(walk.markers[0].elapsed.inSeconds, closeTo(200, 2));
      expect(walk.markers[1].elapsed.inSeconds, closeTo(400, 2));
      expect(
        walk.markers[1].elapsed,
        walk.splits[0].duration + walk.splits[1].duration,
      );
    });

    test('a marker sits on the boundary, not on the nearest fix', () {
      // 5 m/s with a fix a second means the kilometre falls exactly on a fix,
      // so make it miss: 3 m/s puts the boundary at 333.3 s, a third of the way
      // between two fixes. The pin has to be interpolated there or it lands up
      // to a stride's worth of road away from where the kilometre turned over.
      final points = _steady(metresPerSecond: 3, seconds: 400);
      final marker = splitRun(points).markers.single;

      // 1000 m north of the start, in degrees of latitude.
      expect(marker.latitude, closeTo(1000 / 111190, 1 / 111190));
      expect(marker.longitude, 0);
      // And not sitting on either of the fixes that straddle it.
      final fixes = points.map((p) => p.latitude);
      expect(fixes.contains(marker.latitude), isFalse);
    });

    test('a run that never completes a kilometre has no markers', () {
      expect(
        splitMarkersFor(_steady(metresPerSecond: 3, seconds: 60)),
        isEmpty,
      );
      expect(splitMarkersFor(const <RunPoint>[]), isEmpty);
    });
  });
}
