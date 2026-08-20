import 'package:mgk_units/mgk_units.dart';

import 'plan_validator.dart';
import 'standing_plan.dart';

/// Turns today's slots into today's session: sets, reps and a weight.
///
/// A [MovementSlot] says what to train and what has been trained in it. It says
/// nothing about how many sets, how many reps, or what to put on the bar —
/// because those are not properties of the plan, they are properties of *this*
/// session, and they change as the numbers do.
///
/// ## This is where the goal finally does something
///
/// Days decides the split, equipment decides the movements, and injuries rule
/// roles out. The goal has been carried through the whole intake without
/// changing anything, which is correct — it moves rep ranges, and rep ranges
/// live here. Three goals produce two schemes, because "lose fat, keep muscle"
/// and "build muscle" are the same training question with different eating
/// around it: hold the stimulus, keep the volume.
///
/// ## Progression is a rule, not a suggestion
///
/// If the top set moved last time, add one increment. If it did not, hold.
/// That is the whole rule, and it is deliberately dull — a coach that improvises
/// a jump is a coach that occasionally improvises a bad one, and the interesting
/// judgement (why has this stalled, is this fatigue or is it programming) is a
/// conversation rather than a number.
///
/// **No history means no number.** A slot with nothing logged in it gets a null
/// target, which the session screen renders as an empty field exactly the way a
/// hand-added movement does. Inventing a starting weight is the app asserting
/// something only the lifter knows.
abstract final class SessionPrescription {
  /// Sets and reps for a slot, given what somebody is training for.
  ///
  /// Main lifts get fewer reps and one more set than accessories under every
  /// goal: they are the movements progress is measured in, so they carry the
  /// heaviest work and the most of it.
  static ({int sets, int reps}) scheme({
    required bool isMain,
    required TrainingGoal goal,
  }) => switch ((goal, isMain)) {
    (TrainingGoal.strength, true) => (sets: 4, reps: 5),
    (TrainingGoal.strength, false) => (sets: 3, reps: 8),
    (TrainingGoal.muscle, true) => (sets: 4, reps: 8),
    (TrainingGoal.muscle, false) => (sets: 3, reps: 12),
  };

  /// The smallest jump worth making, in kilograms.
  ///
  /// Different by movement class because they are different in the gym: a
  /// barbell takes 2.5 kg because that is the smallest pair of plates most
  /// racks have, and a lateral raise takes 1 kg because the next dumbbell up is
  /// a 20% jump nobody makes cleanly.
  static double incrementKg({required bool isMain}) => isMain ? 2.5 : 1;

  /// What to put on the bar, or null when there is nothing to base it on.
  static Mass? target(MovementSlot slot) {
    if (!slot.hasHistory) return null;
    final moved = slot.sessionsAtSameTop == 0;
    final next = moved
        ? slot.lastTopKg! + incrementKg(isMain: slot.isMain)
        : slot.lastTopKg!;
    return Mass.kilograms(next);
  }

  /// The whole session, in the order the slots are trained.
  static List<PlannedMovement> forDay({
    required List<MovementSlot> slots,
    required TrainingGoal goal,
  }) => <PlannedMovement>[
    for (final s in slots)
      PlannedMovement(
        name: s.movement,
        sets: scheme(isMain: s.isMain, goal: goal).sets,
        reps: scheme(isMain: s.isMain, goal: goal).reps,
        target: target(s),
        // Said only when it is worth saying. A note on every movement is a
        // note nobody reads by the third one.
        note: s.hasStalled
            ? 'Not moved in ${s.sessionsAtSameTop} sessions'
            : null,
      ),
  ];
}

/// What somebody is training for, once it has been reduced to what it changes.
///
/// **Three answers, two schemes.** The intake offers "get stronger", "build
/// muscle" and "lose fat, keep muscle" because those are the three people
/// recognise themselves in. The last two are the same training question — hold
/// the stimulus, keep the volume — and differ in what somebody eats, which is
/// not something this app has any business prescribing.
///
/// Collapsing them here rather than in the intake is deliberate: the label a
/// lifter picked is theirs and worth keeping, and the fact that two labels
/// share a rep scheme is an implementation detail they never need to be told.
enum TrainingGoal {
  strength,
  muscle;

  static TrainingGoal fromAnswer(String answer) =>
      answer.toLowerCase().contains('stronger')
      ? TrainingGoal.strength
      : TrainingGoal.muscle;
}
