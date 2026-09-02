/// **The one runner every shell-driven plate is built around.**
///
/// Lifted out of `shell.dart` when `flows.dart` needed the same seed. Two
/// copies of a fixture is the same failure as two copies of a derivation: the
/// board would keep drawing, and the screen behind `A1` would quietly stop
/// being the screen behind `X3`. The header on `shell.dart` explains at length
/// why a thin fixture makes a board lie; a *forked* one lies more slowly and is
/// harder to notice.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/recording/domain/best_effort.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// A runner training for a marathon, available every day so today always has a
/// session — the plate would otherwise show a rest day about half the time it
/// was regenerated, which is a board that changes what it claims depending on
/// when you look at it.
///
/// [racingIn] moves race day relative to today, which is the whole of what
/// separates an ordinary Tuesday from the taper, the day itself and the morning
/// after (ADR-0027). Everything downstream is derived by the app.
RunnerProfile plateProfile({int racingIn = 112}) => RunnerProfile(
  goalDistanceMeters: 42195,
  eventDate: dateOnly(DateTime.now().add(Duration(days: racingIn))),
  currentWeeklyMeters: 40000,
  longestRecentMeters: 18000,
  daysPerWeek: 7,
  availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
  timeTrialDistanceMeters: 5000,
  timeTrialDuration: const Duration(minutes: 22),
);

/// Runs behind them, so the log, the records and the year all have something
/// real to draw rather than their empty states.
List<RunSummary> plateLog() {
  final now = DateTime.now();
  return <RunSummary>[
    for (var i = 1; i < 40; i++)
      if (i % 2 == 1)
        RunSummary(
          id: 'plate-$i',
          startedAt: now.subtract(Duration(days: i)),
          duration: Duration(minutes: 28 + (i % 9) * 6),
          distanceMeters: 5200 + (i % 9) * 1800,
          avgPaceSecondsPerKm:
              (28 + (i % 9) * 6) * 60 / ((5200 + (i % 9) * 1800) / 1000),
          // Its own shape, so the log tells two runs apart before a word of it
          // is read — see [plateRoute].
          points: plateRoute(i),
          bestEfforts: <BestEffort>[
            if (5200 + (i % 9) * 1800 >= 5000)
              BestEffort(
                distanceMeters: 5000,
                duration: Duration(seconds: 1500 + (i % 7) * 20),
              ),
          ],
        ),
  ];
}

/// Pumps rather than settles.
///
/// The shell loads its plan, its log and its coach asynchronously and then the
/// coach mark plays a 3.4-second reveal, so `pumpAndSettle` would either hang
/// on the animation or land on whichever frame it stopped at. Fixed pumps put
/// the picture at a chosen moment instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// **A different route for every run, because that is the feature.**
///
/// The log draws each run's trace as its thumbnail, so two runs are told apart
/// by their shape before a word is read. Every plate fixture on this board used
/// to build runs with no points at all, and `RouteThumbnail` correctly falls
/// back to a type glyph when a run has no route — so the board drew a column
/// of identical glyphs and reported a shipped feature as missing. It is the
/// thin-fixture failure exactly: the screen was right, the picture was not.
///
/// Runs somebody typed in still get no route, and should not: a treadmill
/// session has no shape, and the glyph is the correct answer for it.
///
/// The curve is a closed loop whose lobes, stretch and rotation all come off
/// [seed], so the shapes differ from each other the way real routes do rather
/// than being one route drawn at different sizes.
List<RunPoint> plateRoute(int seed, {int samples = 30}) {
  const double lat = 51.2300, lng = -0.2050;
  final int lobes = 2 + seed % 4;
  final double stretch = 0.6 + (seed % 5) * 0.18;
  final double turn = (seed % 7) * 0.9;
  final DateTime start = DateTime(2026, 8, 20, 7);
  return <RunPoint>[
    for (var i = 0; i <= samples; i++)
      () {
        final double t = i / samples * 2 * math.pi;
        final double r = 1 + 0.35 * math.sin(lobes * t);
        return RunPoint(
          latitude: lat + 0.010 * math.sin(t + turn) * stretch * r,
          longitude: lng + 0.015 * math.cos(t + turn) * r,
          accuracyMeters: 6,
          timestamp: start.add(Duration(seconds: i * 40)),
        );
      }(),
  ];
}
