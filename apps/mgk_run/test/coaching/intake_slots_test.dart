import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';

void main() {
  final now = DateTime(2026, 7, 25);

  IntakeSlots complete() => IntakeSlots(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 1),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  test('merge overlays only the non-null extracted slots', () {
    const base = IntakeSlots(
      goalDistanceMeters: 42195,
      currentWeeklyMeters: 30000,
    );
    const extracted = IntakeSlots(currentWeeklyMeters: 40000, daysPerWeek: 4);

    final merged = base.merge(extracted);

    expect(merged.goalDistanceMeters, 42195); // preserved
    expect(merged.currentWeeklyMeters, 40000); // overwritten
    expect(merged.daysPerWeek, 4); // added
  });

  test('missingRequired lists empty required slots', () {
    const partial = IntakeSlots(
      shape: PlanShape.block,
      goalDistanceMeters: 42195,
      eventDate: null,
      daysPerWeek: 5,
    );
    expect(
      partial.missingRequired,
      containsAll(<String>[
        'event_date',
        'weekly_volume',
        'longest_run',
        'time_trial',
      ]),
      reason: 'a block claim with no date still owes a date',
    );
    expect(partial.missingRequired, isNot(contains('goal')));
  });

  // The bug ADR-0011 records: every runner was asked for a race date, so a
  // runner who only wanted to run their local parkrun could never finish
  // onboarding — `isComplete` could not return true and the coach circled back
  // to "when is your race?" until it hit the turn cap.
  group('what is required depends on the shape', () {
    test('a rhythm is never asked for a goal or a date', () {
      const parkrun = IntakeSlots(
        shape: PlanShape.rhythm,
        commitments: <PlanCommitment>[
          PlanCommitment(
            weekday: DateTime.saturday,
            distanceMeters: 5000,
            label: 'parkrun',
            timed: true,
          ),
        ],
        currentWeeklyMeters: 20000,
        longestRecentMeters: 8000,
        daysPerWeek: 3,
      );

      expect(parkrun.missingRequired, isEmpty);
      expect(parkrun.isComplete(now), isTrue);
    });

    test('a horizon is asked for the goal but not a date', () {
      const someday = IntakeSlots(
        shape: PlanShape.horizon,
        goalDistanceMeters: 42195,
        currentWeeklyMeters: 30000,
        longestRecentMeters: 15000,
        daysPerWeek: 4,
        timeTrialDistanceMeters: 5000,
        timeTrialDuration: Duration(minutes: 24),
      );

      expect(someday.missingRequired, isEmpty);
      expect(someday.resolvedShape, PlanShape.horizon);
    });

    test('a runner who has said nothing is asked what they want', () {
      const nothing = IntakeSlots();
      expect(nothing.missingRequired, <String>{'intent'});
    });
  });

  // A model told "a marathon one day" will happily answer `block`, which then
  // demands a date that does not exist. The claim is only honoured when its own
  // preconditions hold.
  group('the model proposes a shape, Dart disposes', () {
    test('a block claimed without a date is a horizon', () {
      const claimed = IntakeSlots(
        shape: PlanShape.block,
        goalDistanceMeters: 42195,
      );
      expect(claimed.resolvedShape, PlanShape.horizon);
    });

    test('a block claimed with a date is a block', () {
      final claimed = IntakeSlots(
        shape: PlanShape.block,
        goalDistanceMeters: 42195,
        eventDate: DateTime(2026, 11, 1),
      );
      expect(claimed.resolvedShape, PlanShape.block);
    });

    test('a horizon claimed with no goal falls back to the data', () {
      const claimed = IntakeSlots(shape: PlanShape.horizon, daysPerWeek: 3);
      expect(claimed.resolvedShape, PlanShape.rhythm);
    });

    test('no claim at all is read off the data', () {
      final dated = IntakeSlots(
        goalDistanceMeters: 21097,
        eventDate: DateTime(2026, 11, 1),
      );
      expect(dated.resolvedShape, PlanShape.block);
      expect(const IntakeSlots().resolvedShape, PlanShape.log);
    });
  });

  test('a complete, sane profile is complete with no issues', () {
    expect(complete().sanityIssues(now), isEmpty);
    expect(complete().isComplete(now), isTrue);
  });

  test('flags 200 miles a week as implausible', () {
    final slots = IntakeSlots(currentWeeklyMeters: 321000); // ~200 mi
    expect(
      slots.sanityIssues(now).any((i) => i.slot == 'weekly_volume'),
      isTrue,
    );
  });

  test('flags an event date in the past', () {
    final slots = IntakeSlots(eventDate: DateTime(2026, 1, 1));
    expect(slots.sanityIssues(now).any((i) => i.slot == 'event_date'), isTrue);
  });

  test('flags a longest run that exceeds weekly volume', () {
    final slots = IntakeSlots(
      currentWeeklyMeters: 30000,
      longestRecentMeters: 35000,
    );
    expect(slots.sanityIssues(now).any((i) => i.slot == 'longest_run'), isTrue);
  });

  test('flags an implausible time-trial pace', () {
    // 5k in 8 minutes -> 96 s/km, faster than any human.
    final slots = IntakeSlots(
      timeTrialDistanceMeters: 5000,
      timeTrialDuration: const Duration(minutes: 8),
    );
    expect(slots.sanityIssues(now).any((i) => i.slot == 'time_trial'), isTrue);
  });

  test('a sanity failure blocks completion even with all slots filled', () {
    final slots = complete();
    // Overwrite the event date with a past one via merge.
    final bad = slots.merge(IntakeSlots(eventDate: DateTime(2020, 1, 1)));
    expect(bad.missingRequired, isEmpty);
    expect(bad.isComplete(now), isFalse);
  });
}
