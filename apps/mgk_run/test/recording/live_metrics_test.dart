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
      expect(gpsSignalFor(null), GpsSignal.none);
      expect(GpsSignal.none.measures, isFalse);
    });

    test('a fix too loose to measure with is weak', () {
      // Recorded and drawn, but outside the distance gate — the state the old
      // single-threshold code threw away entirely.
      expect(gpsSignalFor(_p(0, 0, accuracy: 35)), GpsSignal.weak);
      expect(GpsSignal.weak.measures, isFalse);
    });

    test('an open sky is good, and a loose-but-usable fix is fair', () {
      expect(gpsSignalFor(_p(0, 0, accuracy: 5)), GpsSignal.good);
      expect(gpsSignalFor(_p(0, 0, accuracy: 15)), GpsSignal.fair);
      expect(GpsSignal.fair.measures, isTrue);
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

  group('detectAutoPause', () {
    test('a runner who has stopped is detected as stopped', () {
      // Standing still with GPS drift: a summed path would say "moving", the
      // straight-line displacement says otherwise. That is the distinction the
      // whole detector rests on.
      final jitter = <RunPoint>[
        for (var i = 0; i <= 15; i++)
          _p(
            (i.isEven ? 1 : -1) * 0.00003, // ~3 m of drift, back and forth
            0,
            at: Duration(seconds: i),
          ),
      ];
      expect(detectAutoPause(jitter, wasPaused: false), isTrue);
    });

    test('a runner running is not', () {
      final moving = _steady(metresPerSecond: 3.0, seconds: 15);
      expect(detectAutoPause(moving, wasPaused: false), isFalse);
    });

    test('takes more movement to restart than to stop', () {
      // Hysteresis: without it a runner shuffling at a crossing toggles the
      // state on every fix.
      final shuffle = _steady(metresPerSecond: 1.0, seconds: 5); // ~5 m
      expect(detectAutoPause(shuffle, wasPaused: true), isTrue);

      final away = _steady(metresPerSecond: 4.0, seconds: 5); // ~20 m
      expect(detectAutoPause(away, wasPaused: true), isFalse);
    });

    test('too little data does not flip the state either way', () {
      expect(detectAutoPause(<RunPoint>[_p(0, 0)], wasPaused: false), isFalse);
      expect(detectAutoPause(<RunPoint>[_p(0, 0)], wasPaused: true), isTrue);
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
}
