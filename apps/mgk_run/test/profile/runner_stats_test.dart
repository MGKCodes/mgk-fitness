import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

RunSummary _run(DateTime at) => RunSummary(
  startedAt: at,
  duration: const Duration(minutes: 30),
  distanceMeters: 5000,
);

void main() {
  group('week streak', () {
    test('lapses once the gap is real', () {
      // The screen that found this showed "STREAK 4 wk" beside the coach
      // saying "nothing recorded for 20 days" — two numbers on one screen,
      // disagreeing. Counting back from the last run meant a streak could
      // never end, only pause forever.
      final now = DateTime(2026, 8, 10);

      final current = <RunSummary>[
        for (int w = 0; w < 4; w++)
          _run(now.subtract(Duration(days: 7 * w + 1))),
      ];
      expect(RunnerStats.from(current, now: now).currentStreakWeeks, 4);

      final stale = <RunSummary>[
        for (final RunSummary r in current)
          _run(r.startedAt.subtract(const Duration(days: 20))),
      ];
      expect(RunnerStats.from(stale, now: now).currentStreakWeeks, 0);
    });

    test('a run last week still counts, which is what the grace is for', () {
      // Monday, having run on Sunday. Nothing has been missed yet, and calling
      // that a broken streak is how an app picks a fight with somebody who did
      // exactly what was asked.
      expect(
        RunnerStats.from(<RunSummary>[
          _run(DateTime(2026, 8, 9)),
        ], now: DateTime(2026, 8, 10)).currentStreakWeeks,
        1,
      );
    });

    test('no runs is no streak', () {
      expect(
        RunnerStats.from(
          const <RunSummary>[],
          now: DateTime(2026, 8, 10),
        ).currentStreakWeeks,
        0,
      );
    });
  });
}
