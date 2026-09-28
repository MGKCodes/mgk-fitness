import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/week_progress.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// The tally an adaptation is fitted around.
///
/// `weekOutcomes` could already say what became of every day the plan asked
/// for. What it could not say — because rest days are absent from it entirely —
/// is that the runner went out on a Wednesday nobody asked them to. That run is
/// the whole of the complaint these exist for: the coach reshuffled the week
/// generically because nothing it was handed could see the run.
void main() {
  // 2026-07-27 is a Monday.
  final monday = DateTime(2026, 7, 27);

  RunSummary runAt(DateTime at, {double meters = 8000}) => RunSummary(
    startedAt: at,
    duration: const Duration(minutes: 41),
    distanceMeters: meters,
  );

  /// Mon 8 km easy, Thu 8 km easy, Sun 17 km long. Wednesday, Friday and
  /// Saturday are rest.
  TrainingWeek planned() => const TrainingWeek(
    skeletonIndex: 6,
    sessions: <PlannedSession>[
      PlannedSession(
        weekday: DateTime.monday,
        kind: SessionKind.easy,
        distanceMeters: 8000,
      ),
      PlannedSession(
        weekday: DateTime.thursday,
        kind: SessionKind.easy,
        distanceMeters: 8000,
      ),
      PlannedSession(
        weekday: DateTime.sunday,
        kind: SessionKind.long,
        distanceMeters: 17000,
      ),
    ],
  );

  WeekAsRun readOn(
    DateTime now, {
    List<RunSummary> runs = const <RunSummary>[],
    SessionStatus Function(int weekday)? statusFor,
    DateTime? since,
  }) => weekAsRun(
    week: planned(),
    weekStart: monday,
    now: now,
    runs: runs,
    statusFor: statusFor,
    since: since,
  );

  DayAsRun dayOf(WeekAsRun week, int weekday) =>
      week.days.firstWhere((d) => d.weekday == weekday);

  group('the week, day by day', () {
    test('is always seven days in order, rest days included', () {
      // The one difference from `weekOutcomes`, and the reason this exists: an
      // empty day is somewhere a session can be *put*, so a refit has to be
      // able to see it.
      final week = readOn(addDays(monday, 3));
      expect(week.days.length, 7);
      expect(week.days.map((d) => d.weekday), <int>[1, 2, 3, 4, 5, 6, 7]);
      expect(dayOf(week, DateTime.wednesday).prescribed, isNull);
    });

    test('a day the plan asked nothing of has no outcome at all', () {
      // Not `done`, not `missed` — nothing. Marking an unasked-for day done
      // would be the app congratulating itself for a session it never wrote.
      final week = readOn(addDays(monday, 3));
      expect(dayOf(week, DateTime.wednesday).outcome, isNull);
    });
  });

  group('what has been done', () {
    test('a prescribed day with a run on it is done, and carries the run', () {
      final week = readOn(
        addDays(monday, 3),
        runs: <RunSummary>[runAt(monday, meters: 8200)],
      );
      final day = dayOf(week, DateTime.monday);
      expect(day.isDone, isTrue);
      expect(day.ranMeters, 8200);
      expect(week.done.map((d) => d.weekday), <int>[DateTime.monday]);
    });

    test('two runs on one day are one day, and both distances', () {
      // The plan schedules against the day, not the run. A double day is a day.
      final week = readOn(
        addDays(monday, 3),
        runs: <RunSummary>[
          runAt(monday, meters: 5000),
          runAt(DateTime(2026, 7, 27, 18), meters: 4000),
        ],
      );
      expect(dayOf(week, DateTime.monday).ranMeters, 9000);
      expect(week.done.length, 1);
    });

    test('a prescribed day that has gone with no run is missed', () {
      final week = readOn(addDays(monday, 5));
      expect(dayOf(week, DateTime.thursday).isMissed, isTrue);
      expect(week.missed.map((d) => d.weekday), contains(DateTime.thursday));
    });

    test('today is still ahead, never missed', () {
      // The evening is still theirs — the same line `outcomeOn` draws.
      final week = readOn(addDays(monday, 3));
      final thursday = dayOf(week, DateTime.thursday);
      expect(thursday.isMissed, isFalse);
      expect(thursday.hasPassed, isFalse);
      expect(thursday.isRemaining, isTrue);
    });

    test('a day the runner waved off is skipped, not missed', () {
      final week = readOn(
        addDays(monday, 5),
        statusFor: (weekday) => weekday == DateTime.thursday
            ? SessionStatus.skipped
            : SessionStatus.planned,
      );
      expect(dayOf(week, DateTime.thursday).isSkipped, isTrue);
      expect(dayOf(week, DateTime.thursday).isMissed, isFalse);
    });

    test('a day before the plan could ask for anything is not missed', () {
      // A plan cannot be behind on days that predate it. The floor is the
      // caller's to set, for the same reason it is on `missedSessions`.
      final week = readOn(addDays(monday, 5), since: addDays(monday, 2));
      expect(dayOf(week, DateTime.monday).isMissed, isFalse);
    });
  });

  group('a run the plan never asked for', () {
    // 2026-07-29 is the Wednesday; the plan prescribes nothing on it.
    final wednesday = addDays(monday, 2);

    test('is unplanned, and is not mistaken for a completed session', () {
      final week = readOn(
        addDays(monday, 3),
        runs: <RunSummary>[runAt(wednesday, meters: 6000)],
      );
      final day = dayOf(week, DateTime.wednesday);
      expect(day.isUnplanned, isTrue);
      expect(day.isDone, isFalse, reason: 'nothing was prescribed to complete');
      expect(week.unplanned.map((d) => d.weekday), <int>[DateTime.wednesday]);
    });

    test('settles the day, so nothing may be scheduled onto it', () {
      final week = readOn(
        addDays(monday, 3),
        runs: <RunSummary>[
          runAt(monday, meters: 8000),
          runAt(wednesday, meters: 6000),
        ],
      );
      expect(week.settledWeekdays, <int>{DateTime.monday, DateTime.wednesday});
    });

    test('is counted apart from the metres the plan did ask for', () {
      // The split the long-run share rule leans on: only the metres no
      // prescription accounts for get added back before dividing.
      final week = readOn(
        addDays(monday, 3),
        runs: <RunSummary>[
          runAt(monday, meters: 8000),
          runAt(wednesday, meters: 6000),
        ],
      );
      expect(week.ranMeters, 14000);
      expect(week.unplannedMeters, 6000);
    });
  });

  group('what is still ahead', () {
    test('counts only prescribed days that have not gone or been run', () {
      final week = readOn(
        addDays(monday, 3),
        runs: <RunSummary>[runAt(monday, meters: 8000)],
      );
      // Monday done, Thursday today, Sunday to come.
      expect(week.remaining.map((d) => d.weekday), <int>[
        DateTime.thursday,
        DateTime.sunday,
      ]);
      expect(week.remainingMeters, 25000);
    });

    test('a day already run is not still owed', () {
      final week = readOn(
        addDays(monday, 3),
        runs: <RunSummary>[
          runAt(monday, meters: 8000),
          runAt(addDays(monday, 3), meters: 8000),
        ],
      );
      expect(week.remaining.map((d) => d.weekday), <int>[DateTime.sunday]);
    });
  });

  group('whether the week has anything to say', () {
    test('an untouched week ahead of itself has diverged from nothing', () {
      // The gate on the deterministic refit. Rearranging a week that is
      // perfectly on track is the generic reshuffle arriving by another door.
      final week = readOn(monday);
      expect(week.hasDiverged, isFalse);
      expect(week.hasHistory, isFalse);
    });

    test('a run on a rest day is a divergence on its own', () {
      final week = readOn(
        addDays(monday, 3),
        runs: <RunSummary>[runAt(addDays(monday, 2), meters: 6000)],
      );
      expect(week.hasDiverged, isTrue);
    });

    test('a week going exactly to plan has history but has not diverged', () {
      final week = readOn(
        addDays(monday, 3),
        runs: <RunSummary>[runAt(monday, meters: 8000)],
      );
      expect(week.hasHistory, isTrue);
      expect(week.hasDiverged, isFalse);
    });
  });
}
