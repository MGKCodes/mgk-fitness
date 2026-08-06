import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/goal_draft.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';

/// Changing the target is the most destructive thing the coach can propose: the
/// skeleton is derived from the profile, so a new goal or date does not edit a
/// plan, it replaces one. A misheard date costs sixteen weeks of training.
void main() {
  final now = DateTime(2026, 7, 29);
  DateTime inDays(int d) => now.add(Duration(days: d));

  RunnerProfile marathoner() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 15),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
  );

  group('the combinations are plan shapes, not degrees of completeness', () {
    test('a distance and a date is a block', () {
      final draft = GoalDraft(goalDistanceMeters: 21097, eventDate: inDays(90));
      expect(draft.shape, PlanShape.block);
      expect(draft.isValid(now), isTrue);
    });

    test('a distance with no date is a horizon, and is valid', () {
      // "I want to be able to run a marathon" is a complete answer (ADR-0011).
      const draft = GoalDraft(goalDistanceMeters: 42195);
      expect(draft.shape, PlanShape.horizon);
      expect(draft.isValid(now), isTrue);
    });

    test(
      'neither is a rhythm — stepping off a block is a legal thing to do',
      () {
        const draft = GoalDraft();
        expect(draft.shape, PlanShape.rhythm);
        expect(draft.isValid(now), isTrue);
      },
    );

    test('a date with no distance is refused', () {
      // The one combination that is not a shape: a date says nothing about what
      // to train for, so there is no plan to build from it.
      final draft = GoalDraft(eventDate: inDays(90));
      final issues = draft.issues(now);
      expect(issues.map((i) => i.field), contains('event'));
      expect(issues.first.message, contains('needs a distance'));
    });
  });

  group('distances that are not goals', () {
    test('a distance under a kilometre is a misheard number', () {
      const draft = GoalDraft(goalDistanceMeters: 500);
      expect(draft.issues(now).single.field, 'goal');
    });

    test('an ultra is out of scope rather than invalid', () {
      const draft = GoalDraft(goalDistanceMeters: 160000);
      expect(
        draft.issues(now).single.message,
        contains('does not plan ultras'),
      );
    });

    test('zero and infinity are refused, not coerced', () {
      expect(const GoalDraft(goalDistanceMeters: 0).issues(now), isNotEmpty);
      expect(
        const GoalDraft(goalDistanceMeters: double.infinity).issues(now),
        isNotEmpty,
      );
      expect(
        const GoalDraft(goalDistanceMeters: double.nan).issues(now),
        isNotEmpty,
      );
    });

    test('a marathon and a 5k are both fine', () {
      expect(const GoalDraft(goalDistanceMeters: 42195).isValid(now), isTrue);
      expect(const GoalDraft(goalDistanceMeters: 5000).isValid(now), isTrue);
    });
  });

  group('dates a block cannot be built on', () {
    test('a date in the past has already happened', () {
      final draft = GoalDraft(goalDistanceMeters: 42195, eventDate: inDays(-1));
      expect(draft.issues(now).single.message, contains('already passed'));
    });

    test('today is too soon, and says so rather than passing', () {
      final draft = GoalDraft(goalDistanceMeters: 42195, eventDate: now);
      expect(draft.issues(now).single.message, contains('too soon'));
    });

    test('a race next year is fine', () {
      final draft = GoalDraft(
        goalDistanceMeters: 42195,
        eventDate: inDays(300),
      );
      expect(draft.isValid(now), isTrue);
    });

    test('a race three years out is fiction', () {
      final draft = GoalDraft(
        goalDistanceMeters: 42195,
        eventDate: inDays(1200),
      );
      expect(draft.issues(now).single.field, 'event');
    });

    test('the time of day does not decide whether a race has passed', () {
      // Race morning, asked at 11pm the night before: still tomorrow's race.
      final draft = GoalDraft(
        goalDistanceMeters: 42195,
        eventDate: DateTime(2026, 8, 30, 9),
      );
      expect(draft.isValid(DateTime(2026, 7, 29, 23, 59)), isTrue);
    });
  });

  group('applying it', () {
    test('the target changes and the runner does not', () {
      final profile = marathoner();
      final draft = GoalDraft(
        goalDistanceMeters: 21097,
        eventDate: DateTime(2026, 10, 4),
      );
      final next = draft.onto(profile);

      expect(next.goalDistanceMeters, 21097);
      expect(next.eventDate, DateTime(2026, 10, 4));
      // Everything they never mentioned survives.
      expect(next.currentWeeklyMeters, profile.currentWeeklyMeters);
      expect(next.longestRecentMeters, profile.longestRecentMeters);
      expect(next.daysPerWeek, profile.daysPerWeek);
      expect(next.availableWeekdays, profile.availableWeekdays);
    });

    test('stepping off a block actually clears the old race', () {
      // The bug `clearGoalDistance` exists to prevent: a null that reads as
      // "unchanged" leaves the marathon in place, so the runner who said they
      // were done keeps the block they were trying to end.
      const draft = GoalDraft();
      final next = draft.onto(marathoner());

      expect(next.goalDistanceMeters, isNull);
      expect(next.eventDate, isNull);
    });

    test('dropping only the date leaves a horizon, not a block', () {
      const draft = GoalDraft(goalDistanceMeters: 42195);
      final next = draft.onto(marathoner());

      expect(next.goalDistanceMeters, 42195);
      expect(next.eventDate, isNull);
    });

    test('a draft read off a profile is the profile', () {
      final draft = GoalDraft.from(marathoner());
      expect(draft.goalDistanceMeters, 42195);
      expect(draft.eventDate, DateTime(2026, 11, 15));
      expect(draft.changes(marathoner()), isFalse);
    });

    test('moving only the date keeps the distance they never restated', () {
      // "Actually the race is the 12th" is not a request to forget the goal.
      final draft = GoalDraft.from(
        marathoner(),
      ).copyWith(eventDate: DateTime(2026, 12, 12));

      expect(draft.goalDistanceMeters, 42195);
      expect(draft.eventDate, DateTime(2026, 12, 12));
    });
  });

  group('a proposal that changes nothing is not a proposal', () {
    test('the same target is not a change', () {
      // Offering it would ask the runner to approve throwing away their block
      // in exchange for the block they already have.
      expect(GoalDraft.from(marathoner()).changes(marathoner()), isFalse);
    });

    test('the same day at a different hour is still not a change', () {
      final draft = GoalDraft(
        goalDistanceMeters: 42195,
        eventDate: DateTime(2026, 11, 15, 9, 30),
      );
      expect(draft.changes(marathoner()), isFalse);
    });

    test('a different distance is', () {
      const draft = GoalDraft(goalDistanceMeters: 21097);
      expect(draft.changes(marathoner()), isTrue);
    });

    test('clearing the goal is a change', () {
      expect(const GoalDraft().changes(marathoner()), isTrue);
    });
  });
}
