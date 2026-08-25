import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/recording/domain/best_effort.dart';
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

  group('lifetime records', () {
    RunSummary withEfforts(DateTime at, List<BestEffort> efforts) => RunSummary(
      startedAt: at,
      duration: const Duration(minutes: 55),
      distanceMeters: 10500,
      bestEfforts: efforts,
    );

    test('the fastest at each distance wins, whatever run it came from', () {
      final stats = RunnerStats.from(<RunSummary>[
        withEfforts(DateTime(2026, 8, 3), const <BestEffort>[
          BestEffort(distanceMeters: 5000, duration: Duration(minutes: 26)),
          BestEffort(distanceMeters: 10000, duration: Duration(minutes: 54)),
        ]),
        withEfforts(DateTime(2026, 8, 10), const <BestEffort>[
          BestEffort(distanceMeters: 5000, duration: Duration(minutes: 24)),
          BestEffort(distanceMeters: 10000, duration: Duration(minutes: 56)),
        ]),
      ], now: DateTime(2026, 8, 10));

      // Records are not a property of one run: the best 5K and the best 10K
      // can come from different mornings, and usually do.
      expect(stats.bestEffortAt(5000), const Duration(minutes: 24));
      expect(stats.bestEffortAt(10000), const Duration(minutes: 54));
    });

    test('a distance never covered has no entry, rather than a zero', () {
      final stats = RunnerStats.from(<RunSummary>[
        withEfforts(DateTime(2026, 8, 10), const <BestEffort>[
          BestEffort(distanceMeters: 5000, duration: Duration(minutes: 24)),
        ]),
      ], now: DateTime(2026, 8, 10));

      expect(stats.bestEffortAt(21097.5), isNull);
      expect(stats.bestEffortAt(42195), isNull);
    });

    test('an empty log has no records and nothing to explain', () {
      expect(RunnerStats.empty.bestEfforts, isEmpty);
      expect(RunnerStats.empty.hasRecordlessRuns, isFalse);
    });

    test('a long run that set no record is the case worth explaining', () {
      // A marathon typed in by hand. It has no trace, so it sets nothing, and
      // the runner is looking at a marathon in their log beside a dash. That is
      // correct and it is not self-evident, so the page has to be able to say
      // so.
      final stats = RunnerStats.from(<RunSummary>[
        RunSummary(
          startedAt: DateTime(2026, 5, 4),
          duration: const Duration(hours: 3, minutes: 48),
          distanceMeters: 42195,
        ),
      ], now: DateTime(2026, 5, 5));

      expect(stats.hasRecordlessRuns, isTrue);
    });

    test('a run too short to have set one explains itself', () {
      // Under 5 km, so it was never a candidate. Nothing surprising about its
      // silence, and a note about it would be noise on the page of a runner
      // whose records are all correct.
      final stats = RunnerStats.from(<RunSummary>[
        RunSummary(
          startedAt: DateTime(2026, 8, 10),
          duration: const Duration(minutes: 18),
          distanceMeters: 3400,
        ),
      ], now: DateTime(2026, 8, 10));

      expect(stats.hasRecordlessRuns, isFalse);
    });

    test('a five kilometre run with no 5K is exactly the confusing case', () {
      // The boundary, and it belongs on the explaining side. A run whose
      // summary says 5.00 km and whose trace held no continuous 5 km — the GPS
      // dropped, or it came up 3 m short — is the runner asking "I ran a 5K,
      // where is it?", which is the question the note answers.
      final stats = RunnerStats.from(<RunSummary>[
        _run(DateTime(2026, 8, 10)),
      ], now: DateTime(2026, 8, 10));

      expect(stats.hasRecordlessRuns, isTrue);
    });

    test('a traced run that set records explains nothing either', () {
      final stats = RunnerStats.from(<RunSummary>[
        withEfforts(DateTime(2026, 8, 10), const <BestEffort>[
          BestEffort(distanceMeters: 5000, duration: Duration(minutes: 24)),
          BestEffort(distanceMeters: 10000, duration: Duration(minutes: 51)),
        ]),
      ], now: DateTime(2026, 8, 10));

      expect(stats.hasRecordlessRuns, isFalse);
    });
  });
}
