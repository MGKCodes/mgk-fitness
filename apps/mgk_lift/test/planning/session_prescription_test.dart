import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/session_prescription.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan.dart';

MovementSlot slot({bool main = false, double? kg, int? reps, int stale = 0}) =>
    MovementSlot(
      id: 's',
      role: 'r',
      movement: 'Barbell Bench Press',
      isMain: main,
      lastTopKg: kg,
      lastTopReps: reps,
      sessionsAtSameTop: stale,
    );

void main() {
  group('the goal changes the reps, and nothing else does', () {
    test('strength is heavier and shorter than muscle', () {
      expect(
        SessionPrescription.scheme(isMain: true, goal: TrainingGoal.strength),
        (sets: 4, reps: 5),
      );
      expect(
        SessionPrescription.scheme(isMain: true, goal: TrainingGoal.muscle),
        (sets: 4, reps: 8),
      );
    });

    test('main lifts carry more work than accessories under either goal', () {
      for (final g in TrainingGoal.values) {
        final main = SessionPrescription.scheme(isMain: true, goal: g);
        final acc = SessionPrescription.scheme(isMain: false, goal: g);
        expect(main.sets, greaterThan(acc.sets), reason: g.name);
        expect(main.reps, lessThan(acc.reps), reason: g.name);
      }
    });

    test('three answers collapse to two schemes', () {
      // "Lose fat, keep muscle" and "build muscle" are the same training
      // question with different eating around it.
      expect(TrainingGoal.fromAnswer('Get stronger'), TrainingGoal.strength);
      expect(TrainingGoal.fromAnswer('Build muscle'), TrainingGoal.muscle);
      expect(
        TrainingGoal.fromAnswer('Lose fat, keep muscle'),
        TrainingGoal.muscle,
      );
    });
  });

  group('progression', () {
    test('a lift that moved gets one increment', () {
      expect(
        SessionPrescription.target(
          slot(main: true, kg: 85, reps: 6),
        )!.kilograms,
        87.5,
      );
    });

    test('a lift that has not moved holds', () {
      // The interesting judgement -- is this fatigue or is it programming --
      // is a conversation, not a number this should improvise.
      expect(
        SessionPrescription.target(
          slot(main: true, kg: 85, reps: 6, stale: 4),
        )!.kilograms,
        85,
      );
    });

    test('accessories move in smaller steps than barbells', () {
      // The next dumbbell up is a 20% jump nobody makes cleanly.
      expect(SessionPrescription.incrementKg(isMain: true), 2.5);
      expect(SessionPrescription.incrementKg(isMain: false), 1);
      expect(SessionPrescription.target(slot(kg: 12, reps: 12))!.kilograms, 13);
    });

    test('no history means no number, not a guessed one', () {
      // Inventing a starting weight is the app asserting something only the
      // lifter knows. Null renders as a blank field, same as a hand-added
      // movement.
      expect(SessionPrescription.target(slot()), isNull);
    });
  });

  test('a whole day comes out in the order it is trained', () {
    final day = SessionPrescription.forDay(
      slots: <MovementSlot>[
        slot(main: true, kg: 85, reps: 6),
        slot(kg: 12, reps: 12, stale: 6),
        slot(),
      ],
      goal: TrainingGoal.strength,
    );

    expect(day, hasLength(3));
    expect(day.first.sets, 4);
    expect(day.first.reps, 5);
    expect(day.first.target!.kilograms, 87.5);
    expect(day.first.note, isNull);

    // A stalled slot says so, once, where it is worth saying.
    expect(day[1].note, contains('Not moved in 6'));
    expect(day[2].target, isNull);
  });
}
