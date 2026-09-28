import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/week_progress.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// The deterministic refit — the week rebuilt around what has already happened
/// in it.
///
/// The field report these answer: *"it currently just reshuffles the week
/// generically"*. A reshuffle is what you get when the only thing you know about
/// the week is its shape. These are about the invariants, not the arithmetic:
/// what happened stays put, what is gone is written off rather than piled onto
/// the weekend, and a run the plan never asked for is credited instead of
/// ignored.
void main() {
  // 2026-07-27 is a Monday.
  final monday = DateTime(2026, 7, 27);
  final profile = RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 1),
    currentWeeklyMeters: 45000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
  );
  final slot = buildSkeleton(
    profile,
    now: DateTime(2026, 7, 25),
    weeks: 12,
  ).weeks[5];
  final base = buildFallbackWeek(slot, profile);

  RunSummary runAt(DateTime at, {required double meters}) => RunSummary(
    startedAt: at,
    duration: Duration(minutes: (meters / 200).round()),
    distanceMeters: meters,
  );

  WeekAsRun standing(DateTime now, List<RunSummary> runs) => weekAsRun(
    week: base,
    weekStart: monday,
    now: now,
    runs: runs,
    since: monday,
  );

  TrainingWeek refit(WeekAsRun soFar) =>
      refitWeek(week: base, slot: slot, profile: profile, soFar: soFar);

  /// What the week still asks of days the runner has not already run.
  double stillAsked(TrainingWeek week, WeekAsRun soFar) {
    final settled = soFar.settledWeekdays;
    return week.runs
        .where((s) => !settled.contains(s.weekday))
        .fold<double>(0, (sum, s) => sum + s.distanceMeters);
  }

  setUp(() {
    // Preconditions the assertions below lean on. Stated rather than assumed so
    // a change to the deterministic builder says which test it broke and why.
    expect(base.runOn(DateTime.monday), isNotNull);
    expect(base.runOn(DateTime.wednesday), isNull, reason: 'Wednesday is rest');
    expect(base.runOn(DateTime.sunday)?.kind, SessionKind.long);
  });

  group('a day that has been run is settled', () {
    test('a completed session comes through the refit untouched', () {
      final soFar = standing(addDays(monday, 3), <RunSummary>[
        runAt(monday, meters: 8000),
      ]);
      final before = base.runOn(DateTime.monday)!;
      final after = refit(soFar).runOn(DateTime.monday);

      // It happened. Moving it, resizing it or dropping it would show the
      // runner a diff about a run they went out and did.
      expect(after, isNotNull);
      expect(after!.kind, before.kind);
      expect(after.distanceMeters, before.distanceMeters);
    });

    test('and the refit it produces satisfies the rule that says so', () {
      // The builder and the validator drawing the same line, on purpose: one
      // cannot break what the other refuses.
      final soFar = standing(addDays(monday, 3), <RunSummary>[
        runAt(monday, meters: 8000),
        runAt(addDays(monday, 2), meters: 12000),
      ]);
      final result = validateWeek(
        refit(soFar),
        slot,
        profile,
        rules: const PlanRules.adaptation(),
        soFar: soFar,
      );
      expect(
        result.isValid,
        isTrue,
        reason: 'the fallback is held to the same rules: ${result.violations}',
      );
    });

    test('nothing is scheduled onto a day already run off-plan', () {
      // Wednesday was a rest day and the runner went out anyway. Prescribing
      // something on it now would be the plan claiming a run it never asked for.
      final soFar = standing(addDays(monday, 3), <RunSummary>[
        runAt(addDays(monday, 2), meters: 12000),
      ]);
      expect(refit(soFar).runOn(DateTime.wednesday), isNull);
    });

    test('and it never asks for more days than the runner has', () {
      // The unplanned Wednesday spent one of them, prescribed or not.
      final soFar = standing(addDays(monday, 3), <RunSummary>[
        runAt(monday, meters: 8000),
        runAt(addDays(monday, 2), meters: 12000),
      ]);
      expect(refit(soFar).runs.length, lessThanOrEqualTo(profile.daysPerWeek));
    });
  });

  group('a run the plan never asked for is credited', () {
    final now = addDays(monday, 3); // Thursday

    test('by asking less of the days that are left', () {
      // The complaint, in one assertion. Two identical Thursdays, one of them
      // with a 12 km Wednesday behind it: the second must ask for less.
      final without = standing(now, <RunSummary>[runAt(monday, meters: 8000)]);
      final with_ = standing(now, <RunSummary>[
        runAt(monday, meters: 8000),
        runAt(addDays(monday, 2), meters: 12000),
      ]);

      expect(
        stillAsked(refit(with_), with_),
        lessThan(stillAsked(refit(without), without)),
      );
    });

    test('rather than by being ignored and run on top', () {
      // What the runner will have covered by Sunday, if they do what the refit
      // asks: their own week, not their week plus an extra 12 km.
      final soFar = standing(now, <RunSummary>[
        runAt(monday, meters: 8000),
        runAt(addDays(monday, 2), meters: 12000),
      ]);
      final total = soFar.ranMeters + stillAsked(refit(soFar), soFar);
      expect(total, lessThanOrEqualTo(slot.volumeMeters + 1000));
    });
  });

  group('what has gone is written off, not piled up', () {
    test('a missed day is dropped rather than left sitting in the past', () {
      // Thursday, with Tuesday's session missed. Leaving it in the week is what
      // makes Home go on reporting a session the runner can no longer do.
      final soFar = standing(addDays(monday, 3), <RunSummary>[
        runAt(monday, meters: 8000),
      ]);
      expect(soFar.missed.map((d) => d.weekday), contains(DateTime.tuesday));
      expect(refit(soFar).runOn(DateTime.tuesday), isNull);
    });

    test('and nothing at all is scheduled on a day that has gone', () {
      final now = addDays(monday, 4); // Friday
      final soFar = standing(now, <RunSummary>[runAt(monday, meters: 8000)]);
      final settled = soFar.settledWeekdays;

      for (final s in refit(soFar).sessions) {
        final day = soFar.days.firstWhere((d) => d.weekday == s.weekday);
        expect(
          !day.hasPassed || settled.contains(s.weekday),
          isTrue,
          reason: 'weekday ${s.weekday} has gone and was not run',
        );
      }
    });

    test('the days that are left are never asked to make up the shortfall', () {
      // Friday, with Tuesday and Thursday both missed. The arithmetic answer is
      // "you owe 42 km and have two days"; the coaching answer is that a missed
      // easy run is gone. The refit must not exceed what the week already had
      // ahead of it.
      final now = addDays(monday, 4);
      final soFar = standing(now, <RunSummary>[runAt(monday, meters: 8000)]);
      expect(soFar.missed.length, 2);

      final asked = stillAsked(refit(soFar), soFar);
      // The long run is the one miss worth carrying, so the ceiling is what was
      // still ahead plus it — never the whole shortfall.
      expect(asked, lessThanOrEqualTo(soFar.remainingMeters + 1000));
    });

    test('but a missed long run is carried, not written off with the rest', () {
      // Missing an easy run is a Tuesday that got away; missing the long run is
      // a week that did not happen. Built by hand, because the long run only
      // lands mid-week once a runner has already moved it.
      const bespoke = SkeletonWeek(
        index: 6,
        phase: Phase.build,
        volumeMeters: 40000,
        longRunMeters: 14000,
      );
      final moved = TrainingWeek(
        skeletonIndex: bespoke.index,
        sessions: const <PlannedSession>[
          PlannedSession(
            weekday: DateTime.monday,
            kind: SessionKind.easy,
            distanceMeters: 8000,
          ),
          PlannedSession(
            weekday: DateTime.tuesday,
            kind: SessionKind.long,
            distanceMeters: 14000,
          ),
          PlannedSession(
            weekday: DateTime.thursday,
            kind: SessionKind.easy,
            distanceMeters: 10000,
          ),
          PlannedSession(
            weekday: DateTime.sunday,
            kind: SessionKind.easy,
            distanceMeters: 8000,
          ),
        ],
      );
      final fourDays = RunnerProfile(
        goalDistanceMeters: 42195,
        eventDate: DateTime(2026, 11, 1),
        currentWeeklyMeters: 40000,
        longestRecentMeters: 16000,
        daysPerWeek: 4,
        availableWeekdays: const <int>{1, 2, 4, 7},
      );
      final soFar = weekAsRun(
        week: moved,
        weekStart: monday,
        now: addDays(monday, 3),
        runs: <RunSummary>[runAt(monday, meters: 8000)],
        since: monday,
      );

      final result = refitWeek(
        week: moved,
        slot: bespoke,
        profile: fourDays,
        soFar: soFar,
      );

      expect(
        result.runs.any((s) => s.kind == SessionKind.long),
        isTrue,
        reason: 'the session the block hangs on gets another day',
      );
      expect(
        validateWeek(
          result,
          bespoke,
          fourDays,
          rules: const PlanRules.adaptation(),
          soFar: soFar,
        ).isValid,
        isTrue,
      );
    });

    test('a long run the runner waved off is not quietly re-prescribed', () {
      // Skipping is a decision, not a gap. Re-writing it in would be the plan
      // overruling them.
      final now = addDays(monday, 3);
      final soFar = weekAsRun(
        week: base,
        weekStart: monday,
        now: now,
        runs: <RunSummary>[runAt(monday, meters: 8000)],
        statusFor: (weekday) => weekday == DateTime.sunday
            ? SessionStatus.skipped
            : SessionStatus.planned,
        since: monday,
      );
      expect(soFar.skipped.map((d) => d.weekday), contains(DateTime.sunday));
      expect(refit(soFar).runs.any((s) => s.kind == SessionKind.long), isFalse);
    });
  });

  group('the week that comes back is still a training week', () {
    test('a quality session never lands beside one already run', () {
      // Tuesday, with Monday's threshold behind them. The kept day is history
      // and cannot move, so the new session is the one that gives way.
      expect(
        base.runOn(DateTime.monday)!.kind.isHard,
        isTrue,
        reason: 'the fixture depends on Monday carrying the quality session',
      );
      final soFar = standing(addDays(monday, 1), <RunSummary>[
        runAt(monday, meters: 8000),
      ]);
      final result = refit(soFar);

      expect(result.runOn(DateTime.tuesday)?.kind.isHard, isFalse);
      expect(
        validateWeek(
          result,
          slot,
          profile,
          rules: const PlanRules.adaptation(),
          soFar: soFar,
        ).has('back_to_back_hard'),
        isFalse,
      );
    });

    test('with nothing left to give, it keeps what happened and stops', () {
      // Sunday evening, every day run. There is nothing to refit and no honest
      // way to ask for more; a builder that insisted on filling the week would
      // be prescribing into the past.
      final soFar = standing(addDays(monday, 6), <RunSummary>[
        for (final s in base.runs)
          runAt(addDays(monday, s.weekday - 1), meters: s.distanceMeters),
      ]);
      final result = refit(soFar);

      expect(result.runs.length, base.runs.length);
      for (final s in base.runs) {
        expect(result.runOn(s.weekday)?.distanceMeters, s.distanceMeters);
      }
    });

    test('it is marked provisional, like every week no model wrote', () {
      final soFar = standing(addDays(monday, 3), <RunSummary>[
        runAt(monday, meters: 8000),
      ]);
      expect(refit(soFar).provisional, isTrue);
    });
  });
}
