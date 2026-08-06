import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

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
}
