import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/prescribed_distance.dart';
import 'package:mgk_run/src/features/recording/domain/best_effort.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';

/// **A personal best is the fastest continuous stretch of a distance inside a
/// run, and the alternative is wrong in a way that looks right.**
///
/// The 23 Aug test run covered 10.18 km in 58:28. Read the whole run as a 10K
/// and the record is 58:28; the runner's actual 10K inside it was about 57:25,
/// so the easy version understates their own best by a minute and never says
/// so. It gets worse the further past the mark they go — a 21.5 km training run
/// reported as a half marathon is a wildly slow half marathon — which is why
/// these tests are mostly about runs that are *longer* than the record they
/// hold.
///
/// The traces here are laid out along a meridian, where a haversine of a
/// north–south hop is exactly the radius times the angle. That makes "a run of
/// exactly 5 km" a thing a test can actually build, rather than something that
/// lands at 4,998 m and quietly changes what is being asserted.
void main() {
  /// Metres per degree of latitude on the sphere `haversineMeters` uses.
  const double metersPerDegree = 6371000.0 * math.pi / 180.0;

  final start = DateTime(2026, 8, 23, 14, 2);

  RunPoint at(double meters, Duration elapsed, {double accuracy = 5}) =>
      RunPoint(
        latitude: 51.0 + meters / metersPerDegree,
        longitude: -0.1,
        accuracyMeters: accuracy,
        timestamp: start.add(elapsed),
      );

  /// A straight run of [meters] at [secondsPerKm], sampled every [step] metres.
  ///
  /// The sampling interval matters and is not free: `kMaxTraceGap` breaks the
  /// trace at 30 s between fixes, so a fixture that samples too sparsely stops
  /// being one run and starts being several, which is a different test than the
  /// one it looks like.
  List<RunPoint> straight({
    required double meters,
    required double secondsPerKm,
    double step = 50,
    double from = 0,
    Duration since = Duration.zero,
  }) {
    final points = <RunPoint>[];
    for (var covered = 0.0; covered <= meters + 1e-9; covered += step) {
      points.add(
        at(
          from + covered,
          since +
              Duration(
                milliseconds: (covered / 1000 * secondsPerKm * 1000).round(),
              ),
        ),
      );
    }
    return points;
  }

  group('the window itself', () {
    test('a run of exactly the distance is that distance', () {
      // 5 km at 5:00/km, and not a metre more. The window has exactly one
      // position, so this is the case where searching and not searching agree —
      // and the one that would fall off the edge if a sum of a hundred
      // haversines landing at 4,999.999999997 were allowed to disqualify it.
      final trace = straight(meters: 5000, secondsPerKm: 300);

      final best = fastestEffort(trace, 5000);

      expect(best, isNotNull);
      expect(best!.inSeconds, closeTo(1500, 1));
    });

    test('a run well over the distance reports the stretch, not the run', () {
      // 10 km at an even 5:00/km. The run took 50 minutes; the 5 km inside it
      // took 25, and reporting 50 would be the bug this whole file is about.
      final trace = straight(meters: 10000, secondsPerKm: 300);

      expect(fastestEffort(trace, 5000)!.inSeconds, closeTo(1500, 1));
      expect(fastestEffort(trace, 10000)!.inSeconds, closeTo(3000, 1));
    });

    test('a negative split puts the best window at the end', () {
      // 3 km at 6:00/km, then 3 km at 4:00/km. Every 5 km window trades slow
      // metres at the front for fast ones at the back, so the fastest is the
      // last one: 2 km slow (12:00) plus 3 km fast (12:00) — 24 minutes. The
      // first 5 km took 26.
      final trace = <RunPoint>[
        ...straight(meters: 3000, secondsPerKm: 360),
        ...straight(
          meters: 3000,
          secondsPerKm: 240,
          from: 3000,
          since: const Duration(minutes: 18),
        ).skip(1),
      ];

      final best = fastestEffort(trace, 5000);

      expect(best!.inSeconds, closeTo(1440, 1));
      // Belt and braces: the front window is the one a naive scan would find,
      // and it is two minutes slower.
      expect(best.inSeconds, lessThan(1560));
    });

    test('a run shorter than the distance holds no record', () {
      final trace = straight(meters: 4000, secondsPerKm: 300);

      expect(fastestEffort(trace, 5000), isNull);
      expect(bestEffortsFor(trace), isEmpty);
    });

    test('a run with no trace holds no record', () {
      // Hand-entered, or arrived from Health. There is no interior to search,
      // and the whole-run time is deliberately **not** substituted: mixing two
      // kinds of evidence into one records table is how the table stops meaning
      // anything (ADR-0026).
      expect(fastestEffort(const <RunPoint>[], 5000), isNull);
      expect(bestEffortsFor(const <RunPoint>[]), isEmpty);
      // One fix is not a trace either.
      expect(bestEffortsFor(<RunPoint>[at(0, Duration.zero)]), isEmpty);
    });

    test('the edges are interpolated rather than snapped to a fix', () {
      // Sampled every 60 m, so 5 km falls a third of the way through a hop.
      // Snapping to whole fixes would report the 5,040 m window — 1,512 s at
      // this pace — and call it a 5K. Twelve seconds of invented time, in the
      // flattering direction or the robbing one depending on where the fixes
      // happened to land.
      final trace = straight(meters: 5400, secondsPerKm: 300, step: 60);

      expect(fastestEffort(trace, 5000)!.inMilliseconds, closeTo(1500000, 600));
    });

    test('a window never spans a gap in the trace', () {
      // Six kilometres of running with a minute of nothing in the middle — a
      // tunnel, or a pause. Neither half holds five continuous kilometres, and
      // the straight line across the hole is a line nobody ran, so there is no
      // 5K here. Bridging it would credit the runner with the tunnel, which is
      // the fastest kilometre of any run.
      final trace = <RunPoint>[
        ...straight(meters: 3000, secondsPerKm: 300),
        ...straight(
          meters: 3000,
          secondsPerKm: 300,
          from: 3000,
          since: const Duration(minutes: 16),
        ).skip(1),
      ];

      expect(fastestEffort(trace, 5000), isNull);
    });

    test('with a gap, the faster side of it wins', () {
      // 5 km at 5:00/km, a break, then 5 km at 4:30/km. Two segments, each one
      // a candidate, and the record is the better of them.
      final trace = <RunPoint>[
        ...straight(meters: 5000, secondsPerKm: 300),
        ...straight(
          meters: 5000,
          secondsPerKm: 270,
          from: 5000,
          since: const Duration(minutes: 40),
        ),
      ];

      expect(fastestEffort(trace, 5000)!.inSeconds, closeTo(1350, 1));
    });

    test('fixes too poor to measure with do not move the window', () {
      // The same 20 m gate the distance uses. A 45 m fix says roughly where
      // somebody is and is nowhere near precise enough to time a record with,
      // and letting it in would put the window's edge most of a street away.
      final clean = straight(meters: 5000, secondsPerKm: 300);
      final withNoise = <RunPoint>[
        for (var i = 0; i < clean.length; i++) ...<RunPoint>[
          clean[i],
          if (i.isEven)
            RunPoint(
              latitude: clean[i].latitude + 0.002,
              longitude: clean[i].longitude,
              accuracyMeters: 45,
              timestamp: clean[i].timestamp.add(const Duration(seconds: 1)),
            ),
        ],
      ];

      expect(
        fastestEffort(withNoise, 5000)!.inSeconds,
        closeTo(fastestEffort(clean, 5000)!.inSeconds, 1),
      );
    });
  });

  group('what a run contributes', () {
    test('only the distances it actually contains, shortest first', () {
      // The 23 Aug run's shape: over 10 km, nowhere near a half.
      final trace = straight(meters: 10180, secondsPerKm: 345);

      final efforts = bestEffortsFor(trace);

      expect(efforts.map((BestEffort e) => e.distanceMeters).toList(), <double>[
        5000,
        10000,
      ]);
      expect(efforts.first.duration, lessThan(efforts.last.duration));
    });

    test('a distance the run misses is absent, not present and empty', () {
      // A row saying "no half marathon" would be a stored zero by another name,
      // and something folding a lifetime best would have to know to skip it.
      final trace = straight(meters: 6000, secondsPerKm: 300);

      expect(bestEffortsFor(trace), hasLength(1));
      expect(bestEffortsFor(trace).single.distanceMeters, 5000);
    });
  });

  group('the distances themselves', () {
    test('are exactly the ones the coach has a word for', () {
      // The two lists are kept apart on purpose — every feature depends on
      // `recording/domain` and it depends on none of them, so the records
      // cannot import the coach's naming — and this is the seam that stops
      // them drifting. A fifth distance added to one and not the other fails
      // here rather than producing a record with no name, or a name with no
      // record.
      expect(kRecordDistancesMeters, namedRaceDistanceMeters);
      for (final meters in kRecordDistancesMeters) {
        expect(raceName(meters), isNotNull, reason: 'unnamed: $meters m');
      }
    });

    test('are stored exactly, not rounded to something sayable', () {
      // A marathon is 42,195 m. Searching a trace for "42 km" would find a
      // window 195 m short and report a time nobody ran.
      expect(kRecordDistancesMeters, contains(42195.0));
      expect(kRecordDistancesMeters, contains(21097.5));
    });
  });
}
