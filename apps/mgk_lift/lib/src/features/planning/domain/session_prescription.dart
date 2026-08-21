import 'package:mgk_units/mgk_units.dart';

import 'planned_movement.dart';
import 'standing_plan.dart';

/// Turns today's slots into today's session.
///
/// ## What this does and does not decide
///
/// **Sets and reps are not here any more.** They came from a lookup on the
/// goal — four by five for strength, four by eight for size — which made two
/// numbers in a table the definition of how to train a movement. A hinge and a
/// lateral raise do not want the same prescription even in the same session
/// with the same goal, and the evidence is less tidy than the folklore anyway:
/// hypertrophy is available across roughly 5–30 reps, and it is strength that
/// is load-specific (c6-rep-ranges). They are prescribed per slot now, by
/// something that knows about programming.
///
/// **The weight stays here, and only here.** It comes from what this lifter has
/// actually lifted, which is the one thing a coach with all the programming
/// knowledge in the world cannot know about them. That is the same line
/// `SwapValidator` draws — *"the coach prescribes an intensity; the kilograms
/// come from this lifter's own logged sets, or they do not come at all"*.
///
/// ## Progression is deliberately dull
///
/// Claim c5-progressive-overload, and the closest thing to settled that this
/// field has. If the top set moved last time, add one increment. If it did not,
/// hold. That is the whole rule — a coach that improvises a jump improvises a
/// bad one eventually, and the interesting judgement (is this fatigue or is it
/// programming) is a conversation rather than a number.
abstract final class SessionPrescription {
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

  /// What to say when there is no number to give.
  ///
  /// **A blank field is not an instruction.** A movement with no history used to
  /// render as an empty box, which is honest about what the app knows and
  /// useless to somebody standing in front of a rack. Telling them to pick a
  /// weight they could do the top rep count with, comfortably, is the thing a
  /// coach would actually say — and it is still not the app asserting a number
  /// it has no basis for.
  ///
  /// Null once there is history, because then there is a real number.
  static String? startingAdvice(MovementSlot slot) => slot.hasHistory
      ? null
      : 'Pick a weight you could do ${slot.reps} with comfortably, '
            'and leave a couple in the tank.';

  /// The whole session, in the order the slots are trained.
  static List<PlannedMovement> forDay(List<MovementSlot> slots) =>
      <PlannedMovement>[
        for (final s in slots)
          PlannedMovement(
            name: s.movement,
            sets: s.sets,
            reps: s.reps,
            target: target(s),
            // One note, and only where it earns its place. A note on every
            // movement is a note nobody reads by the third one.
            note: s.hasStalled
                ? 'Not moved in ${s.sessionsAtSameTop} sessions'
                : startingAdvice(s),
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
/// It no longer selects a rep scheme. It is passed to the planner as context,
/// where it biases the prescription rather than determining it: per
/// c6-rep-ranges, strength is where the rep range genuinely narrows, and size
/// is available across a wide one.
enum TrainingGoal {
  strength,
  muscle;

  static TrainingGoal fromAnswer(String answer) =>
      answer.toLowerCase().contains('stronger')
      ? TrainingGoal.strength
      : TrainingGoal.muscle;
}
