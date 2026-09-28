import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/race_day.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// Race day, the result, and the end of a plan (ADR-0027).
///
/// The three things worth pinning here are the three judgement calls: where a
/// result comes from, when a plan ends, and what a runner who never raced gets.
/// Everything else in this file exists to stop a horizon or a rhythm growing a
/// race-day surface it has no date to hang on.
void main() {
  // A Monday, so week boundaries are unambiguous.
  final start = DateTime(2026, 3, 2);
  final raceDay = DateTime(2026, 5, 24);

  RunnerProfile blockProfile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: raceDay,
    currentWeeklyMeters: 40000,
    longestRecentMeters: 22000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  /// A goal with no date — ADR-0011's horizon.
  RunnerProfile horizonProfile() => const RunnerProfile(
    goalDistanceMeters: 42195,
    currentWeeklyMeters: 40000,
    longestRecentMeters: 22000,
    daysPerWeek: 5,
    availableWeekdays: <int>{1, 2, 4, 6, 7},
  );

  /// parkrun every Saturday: no goal, no date, nothing to arrive at.
  RunnerProfile rhythmProfile() => const RunnerProfile(
    currentWeeklyMeters: 20000,
    longestRecentMeters: 8000,
    daysPerWeek: 3,
    availableWeekdays: <int>{2, 4, 6},
    commitments: <PlanCommitment>[
      PlanCommitment(
        weekday: DateTime.saturday,
        distanceMeters: 5000,
        label: 'parkrun',
        timed: true,
      ),
    ],
  );

  StoredPlan planFor(RunnerProfile profile) => StoredPlan(
    id: 'plan-1',
    profile: profile,
    skeleton: buildSkeleton(profile, now: start),
    startDate: mondayOf(start),
  );

  RunSummary runOn(
    DateTime day, {
    double meters = 42610,
    Duration duration = const Duration(hours: 3, minutes: 42, seconds: 18),
  }) => RunSummary(
    id: 'run-${day.day}',
    startedAt: DateTime(day.year, day.month, day.day, 9),
    duration: duration,
    distanceMeters: meters,
  );

  group('the day itself', () {
    test('a block far out says nothing at all', () {
      final plan = planFor(blockProfile());
      expect(raceOutlookFor(plan, DateTime(2026, 4, 1)), isNull);
    });

    test('inside the horizon it counts down without taking the day over', () {
      final plan = planFor(blockProfile());
      final out = raceOutlookFor(plan, DateTime(2026, 5, 21))!;

      expect(out.phase, RacePhase.approaching);
      expect(out.daysAway, 3);
      expect(out.headline, 'Marathon in 3 days');
    });

    test('the day before is named rather than counted', () {
      final plan = planFor(blockProfile());
      expect(
        raceOutlookFor(plan, DateTime(2026, 5, 23))!.headline,
        contains('tomorrow'),
      );
    });

    test('race day is its own moment, not a Tuesday', () {
      final plan = planFor(blockProfile());
      final out = raceOutlookFor(plan, raceDay)!;

      expect(out.phase, RacePhase.today);
      expect(out.daysAway, 0);
      expect(out.headline, 'Race day');
      expect(out.name, 'Marathon');
      // The distance is the race, exactly — 42,195 m, not 42 km (ADR-0026's
      // rule about naming a distance you did not measure).
      expect(out.distanceMeters, 42195);
    });

    test('afterwards it asks, and keeps asking for the grace period', () {
      final plan = planFor(blockProfile());

      expect(
        raceOutlookFor(plan, DateTime(2026, 5, 25))!.phase,
        RacePhase.awaiting,
      );
      expect(
        raceOutlookFor(
          plan,
          DateTime(2026, 5, 24).add(const Duration(days: kRaceGraceDays)),
        )!.phase,
        RacePhase.awaiting,
      );
      // Past the grace period the card stops asking, because by then
      // [overdueClosureFor] has answered for the runner.
      expect(
        raceOutlookFor(
          plan,
          DateTime(2026, 5, 24).add(const Duration(days: kRaceGraceDays + 1)),
        ),
        isNull,
      );
    });
  });

  group('a plan with no race grows no race-day surface', () {
    test('a horizon has a goal and nothing to arrive at', () {
      final plan = planFor(horizonProfile());
      for (final day in <DateTime>[
        DateTime(2026, 3, 9),
        raceDay,
        DateTime(2026, 6, 30),
      ]) {
        expect(raceOutlookFor(plan, day), isNull, reason: '$day');
      }
      expect(raceResultFor(plan, <RunSummary>[runOn(raceDay)]), isNull);
      expect(
        overdueClosureFor(plan, <RunSummary>[], DateTime(2027, 1, 1)),
        isNull,
      );
    });

    test('a rhythm never ends and is never asked how it went', () {
      final plan = planFor(rhythmProfile());
      expect(raceOutlookFor(plan, DateTime(2026, 6, 30)), isNull);
      expect(raceResultFor(plan, <RunSummary>[runOn(raceDay)]), isNull);
      expect(
        overdueClosureFor(plan, <RunSummary>[], DateTime(2030, 1, 1)),
        isNull,
      );
    });
  });

  group('the result', () {
    test('is read off the run recorded on the day', () {
      final plan = planFor(blockProfile());
      final result = raceResultFor(plan, <RunSummary>[runOn(raceDay)])!;

      expect(result.source, RaceTimeSource.logged);
      expect(result.time, const Duration(hours: 3, minutes: 42, seconds: 18));
      // The race distance, not the trace's: a marathon is 42,195 m however far
      // the weaving added.
      expect(result.distanceMeters, 42195);
      expect(result.watchDistanceMeters, 42610);
      expect(result.disagrees, isFalse);
    });

    test('an entered chip time wins, and the watch is kept beside it', () {
      final plan = planFor(blockProfile());
      const chip = Duration(hours: 3, minutes: 41, seconds: 30);
      final result = raceResultFor(plan, <RunSummary>[
        runOn(raceDay),
      ], entered: chip)!;

      expect(result.source, RaceTimeSource.entered);
      expect(result.time, chip);
      // A chip time and a GPS time disagreeing is normal, not an error — both
      // are carried so the screen can say so.
      expect(result.disagrees, isTrue);
      expect(
        result.watchTime,
        const Duration(hours: 3, minutes: 42, seconds: 18),
      );
    });

    test('two identical times are not a disagreement', () {
      final plan = planFor(blockProfile());
      const same = Duration(hours: 3, minutes: 42, seconds: 18);
      final result = raceResultFor(plan, <RunSummary>[
        runOn(raceDay),
      ], entered: same)!;

      expect(result.disagrees, isFalse);
      expect(result.watchTime, isNull);
    });

    test('a race the phone sat out is entirely enterable', () {
      final plan = planFor(blockProfile());
      const watched = Duration(hours: 4, minutes: 1);
      final result = raceResultFor(
        plan,
        const <RunSummary>[],
        entered: watched,
      )!;

      expect(result.time, watched);
      expect(result.watchTime, isNull);
      expect(result.watchDistanceMeters, isNull);
      expect(result.disagrees, isFalse);
    });

    test('nothing recorded and nothing typed is not a result', () {
      final plan = planFor(blockProfile());
      expect(raceResultFor(plan, const <RunSummary>[]), isNull);
      // A run on a different day is not the race.
      expect(
        raceResultFor(plan, <RunSummary>[runOn(DateTime(2026, 5, 23))]),
        isNull,
      );
    });

    test('the longest run of race morning is the race, not the shakeout', () {
      final plan = planFor(blockProfile());
      final result = raceResultFor(plan, <RunSummary>[
        runOn(raceDay, meters: 2000, duration: const Duration(minutes: 12)),
        runOn(raceDay),
      ])!;

      expect(result.time, const Duration(hours: 3, minutes: 42, seconds: 18));
    });

    test('pace is over the race distance, not over the trace', () {
      final plan = planFor(blockProfile());
      final result = raceResultFor(plan, <RunSummary>[
        runOn(raceDay, meters: 42610, duration: const Duration(hours: 4)),
      ])!;

      // 4 hours over 42.195 km is 341.3 s/km. Over the 42.61 km the phone
      // measured it would be 338.0 — a different and less useful number,
      // because nobody sets out to run 42.61 km.
      expect(result.paceSecondsPerKm, closeTo(341.3, 0.5));
    });
  });

  group('the plan ends', () {
    test('not while it is still the runner’s to close', () {
      final plan = planFor(blockProfile());
      expect(
        overdueClosureFor(plan, <RunSummary>[runOn(raceDay)], raceDay),
        isNull,
      );
      expect(
        overdueClosureFor(plan, <RunSummary>[
          runOn(raceDay),
        ], raceDay.add(const Duration(days: kRaceGraceDays))),
        isNull,
      );
    });

    test('a run on the day says they raced, whatever they never told us', () {
      final plan = planFor(blockProfile());
      expect(
        overdueClosureFor(plan, <RunSummary>[
          runOn(raceDay),
        ], raceDay.add(const Duration(days: kRaceGraceDays + 1))),
        PlanClosure.raced,
      );
    });

    test('the runner who never races does not stay on the plan forever', () {
      // The case this exists for: injured in week eleven, never started, and
      // never opened the app again. Nothing about that produces a tap.
      final plan = planFor(blockProfile());
      expect(
        overdueClosureFor(plan, const <RunSummary>[], DateTime(2026, 9, 1)),
        PlanClosure.didNotRace,
      );
    });
  });

  group('what the coach says about it', () {
    test('counts the block rather than the runner’s whole life', () {
      final plan = planFor(blockProfile());
      final runs = <RunSummary>[
        // Long before the plan started — a different training year.
        runOn(DateTime(2025, 6, 1), meters: 10000),
        runOn(DateTime(2026, 3, 10), meters: 10000),
        runOn(DateTime(2026, 4, 14), meters: 20000),
        runOn(raceDay),
      ];

      expect(runsDuring(plan, runs), hasLength(3));

      final verdict = raceVerdict(
        plan: plan,
        result: raceResultFor(plan, runs),
        runs: runs,
      );
      expect(verdict.detail, contains('3:42:18'));
      expect(verdict.detail, contains('3 runs'));
    });

    test('has something to say to a runner who did not race', () {
      final plan = planFor(blockProfile());
      final runs = <RunSummary>[runOn(DateTime(2026, 4, 14), meters: 20000)];
      final verdict = raceVerdict(plan: plan, result: null, runs: runs);

      expect(verdict.headline, isNotEmpty);
      // Counted, and counted in English: "1 runs" is the tell that a sentence
      // was assembled rather than written.
      expect(verdict.detail, contains('1 run and'));
    });

    test('the chat opener carries the result so the coach is not asking', () {
      final plan = planFor(blockProfile());
      final opener = raceChatOpener(
        profile: plan.profile,
        result: raceResultFor(plan, <RunSummary>[runOn(raceDay)]),
      );

      expect(opener, contains('marathon'));
      expect(opener, contains('3:42:18'));
    });
  });
}
