import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/session_prescription.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan.dart';

MovementSlot slot({
  bool main = false,
  double? kg,
  int? topReps,
  int stale = 0,
  int sets = 3,
  int reps = 10,
}) => MovementSlot(
  id: 's',
  role: 'r',
  movement: 'Barbell Bench Press',
  isMain: main,
  sets: sets,
  reps: reps,
  lastTopKg: kg,
  lastTopReps: topReps,
  sessionsAtSameTop: stale,
);

void main() {
  group('what this prescribes, and what it does not', () {
    test('sets and reps come from the slot, untouched', () {
      // They are a coaching judgement per movement now, not a lookup on the
      // goal. This only carries them through.
      final day = SessionPrescription.forDay(<MovementSlot>[
        slot(main: true, sets: 5, reps: 3, kg: 100, topReps: 3),
        slot(sets: 2, reps: 20, kg: 10, topReps: 20),
      ]);
      expect(day[0].sets, 5);
      expect(day[0].reps, 3);
      expect(day[1].sets, 2);
      expect(day[1].reps, 20);
    });

    test('the weight is the one thing it decides', () {
      // Because it is the one thing a coach with every bit of programming
      // knowledge still cannot know about this person.
      expect(
        SessionPrescription.target(
          slot(main: true, kg: 85, topReps: 6),
        )!.kilograms,
        87.5,
      );
    });
  });

  group('progression', () {
    test('a lift that moved gets one increment', () {
      expect(
        SessionPrescription.target(
          slot(main: true, kg: 85, topReps: 6),
        )!.kilograms,
        87.5,
      );
    });

    test('a lift that has not moved holds', () {
      // Is this fatigue or is it programming? That is a conversation, not a
      // number this should improvise.
      expect(
        SessionPrescription.target(
          slot(main: true, kg: 85, topReps: 6, stale: 4),
        )!.kilograms,
        85,
      );
    });

    test('accessories move in smaller steps than barbells', () {
      expect(SessionPrescription.incrementKg(isMain: true), 2.5);
      expect(SessionPrescription.incrementKg(isMain: false), 1);
      expect(
        SessionPrescription.target(slot(kg: 12, topReps: 12))!.kilograms,
        13,
      );
    });
  });

  group('when there is no history', () {
    test('there is no number, and that has not changed', () {
      expect(SessionPrescription.target(slot()), isNull);
    });

    test('but there is an instruction, which is new', () {
      // A blank field is honest about what the app knows and useless to
      // somebody standing in front of a rack.
      final advice = SessionPrescription.startingAdvice(slot(reps: 10));
      expect(advice, contains('10'));
      expect(advice, contains('comfortably'));
    });

    test('it names the rep count the slot actually asks for', () {
      expect(
        SessionPrescription.startingAdvice(slot(reps: 20)),
        contains('20'),
      );
    });

    test('and it goes away once there is a real number', () {
      expect(
        SessionPrescription.startingAdvice(slot(kg: 60, topReps: 8)),
        isNull,
      );
    });
  });

  test('a stall is worth more than starting advice, and only one is shown', () {
    // A movement cannot be both stalled and un-started, but the note has one
    // slot and the ordering should be deliberate rather than incidental.
    final day = SessionPrescription.forDay(<MovementSlot>[
      slot(kg: 12, topReps: 12, stale: 6),
      slot(),
    ]);
    expect(day[0].note, contains('Not moved in 6'));
    expect(day[1].note, contains('comfortably'));
  });

  test('the goal no longer picks a scheme', () {
    // It is context for the planner now: per c6, strength is where the rep
    // range narrows and size is available across a wide one.
    expect(TrainingGoal.fromAnswer('Get stronger'), TrainingGoal.strength);
    expect(TrainingGoal.fromAnswer('Build muscle'), TrainingGoal.muscle);
    expect(
      TrainingGoal.fromAnswer('Lose fat, keep muscle'),
      TrainingGoal.muscle,
    );
  });
}
