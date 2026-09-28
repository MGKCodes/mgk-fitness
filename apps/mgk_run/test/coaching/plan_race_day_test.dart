import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

/// **Race day is the event, not a training day** (ADR-0027).
///
/// The ADR has said so since it was written, and said it about the *screen*:
/// what Home draws on the morning of a race, what it draws the day after, and
/// how a block closes. Nothing ever said it about the plan's own contents, so
/// nothing stopped the final week prescribing a run on the Sunday the race was
/// on — which is what the build 12 field test found in row D4, on a real plan,
/// on a phone.
///
/// Two levels, because one is not enough. The validator refuses it whoever
/// proposed it, which is what holds when the model is in the loop; the builder
/// avoids it by construction, which is what holds when the model is not
/// reachable and Dart writes the week instead.
void main() {
  /// A block ending on a Sunday, with the runner available every day — the
  /// shape that produces the defect. `_spread` keeps the latest available
  /// weekday for the long run, so left alone the long run lands on the race.
  RunnerProfile racingOn(DateTime race) => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: race,
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
  );

  group('the validator refuses a session on race day', () {
    test('whatever kind of session it is', () {
      // A Sunday, and the Monday its week starts on.
      final race = DateTime(2026, 11, 15);
      final weekStart = mondayOf(race);
      final profile = racingOn(race);
      final skeleton = buildSkeleton(profile, now: DateTime(2026, 9, 4));
      final slot = skeleton.weeks.last;

      final onTheDay = TrainingWeek(
        skeletonIndex: slot.index,
        sessions: <PlannedSession>[
          PlannedSession(
            weekday: DateTime.sunday,
            kind: SessionKind.easy,
            distanceMeters: 5000,
          ),
        ],
      );

      final result = validateWeek(
        onTheDay,
        slot,
        profile,
        weekStart: weekStart,
      );

      expect(
        result.violations.map((v) => v.code),
        contains('session_on_race_day'),
      );
    });

    test('and says nothing about a week that does not contain the race', () {
      final race = DateTime(2026, 11, 15);
      final profile = racingOn(race);
      final skeleton = buildSkeleton(profile, now: DateTime(2026, 9, 4));
      final slot = skeleton.weeks.first;

      final ordinary = buildFallbackWeek(slot, profile);
      final result = validateWeek(
        ordinary,
        slot,
        profile,
        // Week one, months before the race.
        weekStart: DateTime(2026, 9, 7),
      );

      expect(
        result.violations.map((v) => v.code),
        isNot(contains('session_on_race_day')),
      );
    });

    test('and is silent when the caller has no calendar to offer', () {
      // The plan model carries no dates by design, so most callers cannot
      // answer this question. They must not be punished for it.
      final race = DateTime(2026, 11, 15);
      final profile = racingOn(race);
      final skeleton = buildSkeleton(profile, now: DateTime(2026, 9, 4));
      final slot = skeleton.weeks.last;

      final result = validateWeek(
        buildFallbackWeek(slot, profile),
        slot,
        profile,
      );

      expect(
        result.violations.map((v) => v.code),
        isNot(contains('session_on_race_day')),
      );
    });
  });

  group('the builder leaves race day alone', () {
    test('and still fills the week from the days that remain', () {
      final race = DateTime(2026, 11, 15); // a Sunday
      final profile = racingOn(race);
      final skeleton = buildSkeleton(profile, now: DateTime(2026, 9, 4));
      final slot = skeleton.weeks.last;

      final week = buildFallbackWeek(
        slot,
        profile,
        unusableWeekdays: const <int>{DateTime.sunday},
      );

      expect(
        week.sessions
            .where((s) => s.kind != SessionKind.rest)
            .map((s) => s.weekday),
        isNot(contains(DateTime.sunday)),
        reason: 'the race is the session; nothing else may be scheduled on it',
      );
      expect(
        week.runs,
        isNotEmpty,
        reason: 'a taper week still has running in it',
      );
    });

    test('and ignores the exclusion rather than building nothing', () {
      // A runner available only on the day of the race. Refusing to build a
      // week at all would be worse than building one they can argue with.
      final profile = RunnerProfile(
        goalDistanceMeters: 42195,
        eventDate: DateTime(2026, 11, 15),
        currentWeeklyMeters: 40000,
        longestRecentMeters: 18000,
        daysPerWeek: 1,
        availableWeekdays: const <int>{DateTime.sunday},
      );
      final skeleton = buildSkeleton(profile, now: DateTime(2026, 9, 4));

      final week = buildFallbackWeek(
        skeleton.weeks.last,
        profile,
        unusableWeekdays: const <int>{DateTime.sunday},
      );

      expect(week.runs, isNotEmpty);
    });
  });
}
