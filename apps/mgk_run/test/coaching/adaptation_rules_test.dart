import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/week_adaptation.dart';
import 'package:mgk_run/src/features/coaching/domain/week_progress.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// Names the weekday a case runs on, so a failure says which one broke.
String _dayName(int weekday) => const <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][weekday - 1];

/// The validator has two jobs and they pull in opposite directions.
///
/// Against a *generated* week it enforces fidelity to the plan, because a model
/// that quietly ignored the slot is the failure it exists to catch. Against a
/// week the *runner* asked to change, that same strictness refuses the change
/// for being a change — which would make the coach useless exactly when it
/// matters most.
void main() {
  final profile = RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 15),
    currentWeeklyMeters: 45000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );
  final slot = buildSkeleton(
    profile,
    now: DateTime(2026, 7, 26),
    weeks: 12,
  ).weeks[5];
  final planned = buildFallbackWeek(slot, profile);

  /// The week with its long run cut roughly in half — a sore calf, say.
  TrainingWeek withEasierLongRun() => TrainingWeek(
    skeletonIndex: slot.index,
    sessions: <PlannedSession>[
      for (final s in planned.sessions)
        if (s.kind == SessionKind.long)
          PlannedSession(
            weekday: s.weekday,
            kind: SessionKind.easy,
            distanceMeters: s.distanceMeters * 0.5,
          )
        else
          s,
    ],
  );

  /// The week with today's session dropped entirely.
  TrainingWeek withOneFewerSession() => TrainingWeek(
    skeletonIndex: slot.index,
    sessions: planned.sessions.skip(1).toList(),
  );

  group('planning rules keep a generated week honest', () {
    test('a halved long run is refused', () {
      final result = validateWeek(withEasierLongRun(), slot, profile);
      expect(result.isValid, isFalse);
      expect(result.has('long_run_slot'), isTrue);
    });

    test('a dropped session is refused', () {
      final result = validateWeek(withOneFewerSession(), slot, profile);
      expect(result.has('session_count'), isTrue);
    });
  });

  group('adaptation rules let the runner change their own week', () {
    const rules = PlanRules.adaptation();

    test('"make Sunday easier" is allowed', () {
      final result = validateWeek(
        withEasierLongRun(),
        slot,
        profile,
        rules: rules,
      );
      expect(
        result.isValid,
        isTrue,
        reason:
            'refusing this refuses the whole point of adaptation: '
            '${result.violations}',
      );
    });

    test('"I can only get out four times" is allowed', () {
      final result = validateWeek(
        withOneFewerSession(),
        slot,
        profile,
        rules: rules,
      );
      expect(result.has('session_count'), isFalse);
    });
  });

  group('what protects the runner still holds', () {
    const rules = PlanRules.adaptation();

    test('a session on an unavailable day is still refused', () {
      // Wednesday is not in availableWeekdays.
      final week = TrainingWeek(
        skeletonIndex: slot.index,
        sessions: <PlannedSession>[
          const PlannedSession(
            weekday: DateTime.wednesday,
            kind: SessionKind.easy,
            distanceMeters: 8000,
          ),
        ],
      );
      expect(
        validateWeek(week, slot, profile, rules: rules).has('unavailable_day'),
        isTrue,
      );
    });

    test('back-to-back hard days are still refused', () {
      final week = TrainingWeek(
        skeletonIndex: slot.index,
        sessions: <PlannedSession>[
          const PlannedSession(
            weekday: DateTime.monday,
            kind: SessionKind.threshold,
            distanceMeters: 8000,
          ),
          const PlannedSession(
            weekday: DateTime.tuesday,
            kind: SessionKind.interval,
            distanceMeters: 8000,
          ),
        ],
      );
      expect(
        validateWeek(
          week,
          slot,
          profile,
          rules: rules,
        ).has('back_to_back_hard'),
        isTrue,
      );
    });

    test('more sessions than the runner has days is still refused', () {
      final week = TrainingWeek(
        skeletonIndex: slot.index,
        sessions: <PlannedSession>[
          for (final day in <int>[1, 2, 3, 4, 5, 6])
            PlannedSession(
              weekday: day,
              kind: SessionKind.easy,
              distanceMeters: 6000,
            ),
        ],
      );
      expect(
        validateWeek(week, slot, profile, rules: rules).has('session_count'),
        isTrue,
        reason: 'fewer is the runner\'s call; more is the model overreaching',
      );
    });

    test('a long run over the absolute ceiling is still refused', () {
      final week = TrainingWeek(
        skeletonIndex: slot.index,
        sessions: <PlannedSession>[
          const PlannedSession(
            weekday: DateTime.sunday,
            kind: SessionKind.long,
            distanceMeters: 45000,
          ),
        ],
      );
      expect(
        validateWeek(week, slot, profile, rules: rules).has('long_run_ceiling'),
        isTrue,
      );
    });
  });

  // 2026-07-27 is a Monday — the week `planned` is taken to be living in.
  final monday = DateTime(2026, 7, 27);

  RunSummary runAt(DateTime at, {required double meters}) => RunSummary(
    startedAt: at,
    duration: Duration(minutes: (meters / 200).round()),
    distanceMeters: meters,
  );

  group('a session already run is not up for negotiation', () {
    const rules = PlanRules.adaptation();
    final thursday = addDays(monday, 3);
    final ranMonday = <RunSummary>[runAt(monday, meters: 8000)];

    WeekAsRun standing() => weekAsRun(
      week: planned,
      weekStart: monday,
      now: thursday,
      runs: ranMonday,
      since: monday,
    );

    /// [planned] with Monday's session put through [change] — null removes it.
    TrainingWeek mondayBecomes(
      PlannedSession? Function(PlannedSession) change,
    ) {
      final replacement = change(planned.runOn(DateTime.monday)!);
      return TrainingWeek(
        skeletonIndex: planned.skeletonIndex,
        sessions: <PlannedSession>[
          for (final s in planned.sessions)
            if (s.weekday != DateTime.monday) s else ?replacement,
        ],
      );
    }

    test('leaving it exactly as it was passes', () {
      expect(
        validateWeek(
          planned,
          slot,
          profile,
          rules: rules,
          soFar: standing(),
        ).has('session_already_done'),
        isFalse,
      );
    });

    test('dropping it is refused', () {
      // The runner would otherwise be shown "Monday — removed" for a run they
      // went out and did.
      expect(
        validateWeek(
          mondayBecomes((_) => null),
          slot,
          profile,
          rules: rules,
          soFar: standing(),
        ).has('session_already_done'),
        isTrue,
      );
    });

    test('moving it to another day is refused', () {
      final moved = TrainingWeek(
        skeletonIndex: planned.skeletonIndex,
        sessions: <PlannedSession>[
          for (final s in planned.sessions)
            if (s.weekday == DateTime.monday)
              PlannedSession(
                weekday: DateTime.wednesday,
                kind: s.kind,
                distanceMeters: s.distanceMeters,
              )
            else
              s,
        ],
      );
      expect(
        validateWeek(
          moved,
          slot,
          profile,
          rules: rules,
          soFar: standing(),
        ).has('session_already_done'),
        isTrue,
      );
    });

    test('resizing it is refused', () {
      final shrunk = mondayBecomes(
        (s) => PlannedSession(
          weekday: s.weekday,
          kind: s.kind,
          distanceMeters: s.distanceMeters - 3000,
        ),
      );
      expect(
        validateWeek(
          shrunk,
          slot,
          profile,
          rules: rules,
          soFar: standing(),
        ).has('session_already_done'),
        isTrue,
      );
    });

    test('and so is changing what it was', () {
      final relabelled = mondayBecomes(
        (s) => PlannedSession(
          weekday: s.weekday,
          kind: s.kind == SessionKind.easy
              ? SessionKind.recovery
              : SessionKind.easy,
          distanceMeters: s.distanceMeters,
        ),
      );
      expect(
        validateWeek(
          relabelled,
          slot,
          profile,
          rules: rules,
          soFar: standing(),
        ).has('session_already_done'),
        isTrue,
      );
    });

    test('but a caller with no log to offer is not punished for it', () {
      // Opt-in, like the calendar rules above it. Most callers cannot answer
      // this question and must not be refused for staying quiet.
      expect(
        validateWeek(
          mondayBecomes((_) => null),
          slot,
          profile,
          rules: rules,
        ).has('session_already_done'),
        isFalse,
      );
    });

    test('and a day nobody has run yet may still be dropped', () {
      // The whole point of the relaxed rules survives: the past is pinned, the
      // future is as free as it ever was.
      final sunday = planned.runOn(DateTime.sunday)!;
      final withoutSunday = TrainingWeek(
        skeletonIndex: planned.skeletonIndex,
        sessions: <PlannedSession>[
          for (final s in planned.sessions)
            if (s.weekday != sunday.weekday) s,
        ],
      );
      final result = validateWeek(
        withoutSunday,
        slot,
        profile,
        rules: rules,
        soFar: standing(),
      );
      expect(result.has('session_already_done'), isFalse);
      expect(result.has('session_count'), isFalse);
    });
  });

  group('a change confined to days still ahead is never refused for it', () {
    // The rule that `chat_adaptation_test.dart` leans on, pinned here so it
    // cannot quietly stop being true. That file drives the whole shell through
    // `DateTime.now()`, so it exercises exactly one of these seven cases on any
    // given run — and the one it exercised on the day `soFar` was wired in was
    // the one where its fixture edited a session the runner had already done.
    // A suite that is right six days in seven is not right.
    //
    // The shape is the shell's own: a week-1 plan, whose `since` floor is today
    // (a plan cannot be behind on days that predate it), and two runs at a day
    // and four days back. Depending on the weekday those land on prescribed
    // days, on rest days, or in the week before — all three, and the answer has
    // to be the same.
    const rules = PlanRules.adaptation();
    final open = RunnerProfile(
      goalDistanceMeters: 42195,
      eventDate: DateTime(2027, 1, 1),
      currentWeeklyMeters: 40000,
      longestRecentMeters: 18000,
      daysPerWeek: 5,
      availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
    );

    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
      test('on a ${_dayName(weekday)}', () {
        // 2026-08-31 is a Monday; week 1 is anchored to it.
        final weekStart = DateTime(2026, 8, 31);
        final now = addDays(weekStart, weekday - 1);
        final week1 = buildSkeleton(open, now: now, weeks: 12).weeks.first;
        final week = buildFallbackWeek(week1, open);

        final soFar = weekAsRun(
          week: week,
          weekStart: weekStart,
          now: now,
          runs: <RunSummary>[
            runAt(addDays(now, -1), meters: 6000),
            runAt(addDays(now, -4), meters: 10000),
          ],
          // Week 1: the plan cannot be held to days that predate it.
          since: now,
        );

        // The last session still to come, a kilometre shorter — the smallest
        // honest change a coach could offer, and the one thing that is always
        // available whatever day it is.
        final ahead = week.runs.where((s) => s.weekday >= weekday).toList()
          ..sort((a, b) => a.weekday.compareTo(b.weekday));
        expect(
          ahead,
          isNotEmpty,
          reason: 'there is always something left of the week to change',
        );
        final last = ahead.last;
        final revised = TrainingWeek(
          skeletonIndex: week.skeletonIndex,
          sessions: <PlannedSession>[
            for (final s in week.sessions)
              if (!identical(s, last))
                s
              else
                PlannedSession(
                  weekday: s.weekday,
                  kind: s.kind,
                  distanceMeters: s.distanceMeters - 1000,
                ),
          ],
        );

        final result = validateWeek(
          revised,
          week1,
          open,
          rules: rules,
          soFar: soFar,
        );
        expect(
          result.isValid,
          isTrue,
          reason:
              'nothing settled was touched, so nothing may refuse it: '
              '${result.violations}',
        );
        expect(
          diffWeek(week, revised),
          isNotEmpty,
          reason: 'a change the runner can be shown, not a no-op',
        );
      });
    }
  });

  group('the long run share judges what is being asked for', () {
    const rules = PlanRules.adaptation();

    test('a long run already run is not a lopsided week', () {
      // 17 km of a 32 km week is 53% on paper. It is also Saturday, and it
      // happened — there is nothing the runner could change to satisfy the rule,
      // so refusing hands them a refusal with no action in it.
      final mostlyDone = TrainingWeek(
        skeletonIndex: slot.index,
        sessions: const <PlannedSession>[
          PlannedSession(
            weekday: DateTime.monday,
            kind: SessionKind.easy,
            distanceMeters: 8000,
          ),
          PlannedSession(
            weekday: DateTime.saturday,
            kind: SessionKind.long,
            distanceMeters: 17000,
          ),
          PlannedSession(
            weekday: DateTime.sunday,
            kind: SessionKind.easy,
            distanceMeters: 7000,
          ),
        ],
      );
      final soFar = weekAsRun(
        week: mostlyDone,
        weekStart: monday,
        now: addDays(monday, 6),
        runs: <RunSummary>[
          runAt(monday, meters: 8000),
          runAt(addDays(monday, 5), meters: 17000),
        ],
        since: monday,
      );

      expect(
        validateWeek(
          mostlyDone,
          slot,
          profile,
          rules: rules,
          soFar: soFar,
        ).has('long_run_fraction'),
        isFalse,
      );
      // And with no log it is exactly the violation it looks like, which is the
      // right answer for a week being written rather than lived in.
      expect(
        validateWeek(
          mostlyDone,
          slot,
          profile,
          rules: rules,
        ).has('long_run_fraction'),
        isTrue,
      );
    });

    test('an unplanned run is added back before the share is worked out', () {
      // A refit credits a 12 km Wednesday by prescribing 12 km less, so the week
      // the runner actually runs is unchanged while the number this divides by
      // is 12 km smaller. Without the credit, their extra run reads as a
      // violation.
      final credited = TrainingWeek(
        skeletonIndex: slot.index,
        sessions: const <PlannedSession>[
          PlannedSession(
            weekday: DateTime.monday,
            kind: SessionKind.easy,
            distanceMeters: 8000,
          ),
          PlannedSession(
            weekday: DateTime.sunday,
            kind: SessionKind.long,
            distanceMeters: 13000,
          ),
        ],
      );
      final soFar = weekAsRun(
        week: credited,
        weekStart: monday,
        now: addDays(monday, 3),
        runs: <RunSummary>[
          runAt(monday, meters: 8000),
          runAt(addDays(monday, 2), meters: 12000),
        ],
        since: monday,
      );

      expect(soFar.unplannedMeters, 12000);
      expect(
        validateWeek(
          credited,
          slot,
          profile,
          rules: rules,
          soFar: soFar,
        ).has('long_run_fraction'),
        isFalse,
      );
      expect(
        validateWeek(
          credited,
          slot,
          profile,
          rules: rules,
        ).has('long_run_fraction'),
        isTrue,
      );
    });

    test('a long run still ahead is judged as strictly as ever', () {
      // The relaxation is about history, not about what a model may prescribe.
      final ahead = TrainingWeek(
        skeletonIndex: slot.index,
        sessions: const <PlannedSession>[
          PlannedSession(
            weekday: DateTime.monday,
            kind: SessionKind.easy,
            distanceMeters: 8000,
          ),
          PlannedSession(
            weekday: DateTime.sunday,
            kind: SessionKind.long,
            distanceMeters: 20000,
          ),
        ],
      );
      final soFar = weekAsRun(
        week: ahead,
        weekStart: monday,
        now: addDays(monday, 3),
        runs: <RunSummary>[runAt(monday, meters: 8000)],
        since: monday,
      );

      expect(
        validateWeek(
          ahead,
          slot,
          profile,
          rules: rules,
          soFar: soFar,
        ).has('long_run_fraction'),
        isTrue,
      );
    });
  });
}
