import 'package:meta/meta.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../stats/domain/training_stats.dart';
import '../../tracking/data/exercise_lookup.dart';
import '../../tracking/domain/session.dart';
import 'plan_proposal.dart';
import 'planned_movement.dart';

/// Checks a movement the coach offered mid-session, and works out its weight.
///
/// **What is left of the week validator.** This class used to check a whole
/// proposed week as well — the right number of sessions, on days the lifter
/// trains, in the right order. A standing plan has no weeks to check, and
/// `PlanShape` took over that job by asking what a plan DOES rather than
/// whether it matches a template. The swap half survived unchanged, because
/// swapping a movement mid-session is the same problem it always was.
///
/// **This is where "targets come from your own numbers" stops being a sentence
/// and starts being enforced.** The coach prescribes an intensity; the
/// kilograms come from this lifter's own logged sets, or they do not come at
/// all. That rule is kept by having nowhere to put a weight in the schema, and
/// by this being the only thing that fills one in.
@immutable
class SwapValidator {
  const SwapValidator({ExerciseLookup? lookup, this.roundingKg = 2.5})
    : _lookup = lookup;
  final ExerciseLookup? _lookup;

  /// What a weight is rounded to.
  ///
  /// 2.5 kg is the smallest change most people can actually make to a barbell —
  /// a 1.25 kg plate on each side. A target of 84.7 kg is not a target, it is a
  /// number nobody can load, and it makes the whole plan read as generated.
  final double roundingKg;

  /// Keeps the options this lifter could actually do, and prices them.
  ///
  /// **Dropping an option is not an error.** The reply reaches them whatever
  /// happens to the options — see [SwapProposal] — so a coach that named three
  /// movements and got two past the catalogue has still answered the question.
  SwapVerdict checkSwap(SwapProposal proposal, {required List<Session> log}) {
    final options = proposal.options;
    if (options == null) {
      return SwapVerdict(reply: proposal.reply, dropped: 0);
    }

    final lookup = _lookup ?? ExerciseLookup();
    final kept = <PlannedMovement>[];
    final why = <String>[];
    var dropped = 0;

    for (final option in options) {
      final pct = option.intensityPct;
      final usable =
          option.name.isNotEmpty &&
          lookup.find(option.name) != null &&
          option.sets >= 1 &&
          option.sets <= 10 &&
          option.reps >= 1 &&
          option.reps <= 20 &&
          (pct == null ||
              (pct >= 40 &&
                  pct <= 100 &&
                  _intensitySuitsReps(pct, option.reps)));

      if (!usable) {
        dropped++;
        continue;
      }
      kept.add(
        PlannedMovement(
          name: option.name,
          sets: option.sets,
          reps: option.reps,
          target: _target(
            ProposedMovement(
              name: option.name,
              sets: option.sets,
              reps: option.reps,
              intensityPct: pct,
            ),
            log,
          ),
        ),
      );
      why.add(option.why);
    }

    return SwapVerdict(
      reply: proposal.reply,
      replaces: proposal.replaces,
      options: kept,
      why: why,
      dropped: dropped,
    );
  }

  /// The weight to put in front of the lifter, or null.
  ///
  /// **Null is a real prescription**, not a missing value: "3×8 on the cable
  /// row, leave two in the tank" is how most accessory work is actually
  /// programmed. It happens whenever there is no intensity to resolve, or no
  /// qualifying set in their log to resolve it against — a lifter two weeks in
  /// will have very few, and inventing numbers for the rest is exactly the
  /// failure this whole path exists to prevent.
  Mass? _target(ProposedMovement movement, List<Session> log) {
    final pct = movement.intensityPct;
    if (pct == null) return null;

    final best = TrainingStats.bestOneRepMax(log, movement.name);
    if (best == null) return null;

    final raw = best.estimate.kilograms * pct / 100;
    final rounded = (raw / roundingKg).round() * roundingKg;
    // Rounding down to nothing would prescribe an empty bar. Below one
    // increment there is no honest number to give.
    if (rounded < roundingKg) return null;
    return Mass.kilograms(rounded);
  }

  /// Whether a rep count and an intensity describe the same set.
  ///
  /// Loose on purpose — this rejects the nonsense (twelve reps at ninety
  /// percent) without arguing about whether a five at eighty-two is really a
  /// five. The ceilings come from the same territory Epley is fitted to, which
  /// is why `estimateOneRepMax` stops at twelve reps for the same reason.
  static bool _intensitySuitsReps(int pct, int reps) {
    if (reps <= 3) return pct >= 80;
    if (reps <= 6) return pct >= 70 && pct <= 95;
    if (reps <= 10) return pct >= 55 && pct <= 87;
    return pct <= 80;
  }
}

@immutable
class SwapVerdict {
  const SwapVerdict({
    required this.reply,
    required this.dropped,
    this.replaces,
    this.options = const <PlannedMovement>[],
    this.why = const <String>[],
  });

  /// Always shown. Even with nothing usable behind it, the coach said
  /// something, and "just skip it today" is a complete answer.
  final String reply;

  /// The movement being replaced, or null when nothing was proposed.
  final String? replaces;

  /// The alternatives that passed, best first, with their targets resolved.
  final List<PlannedMovement> options;

  /// Why each kept option, index-aligned with [options].
  final List<String> why;

  /// How many were discarded for naming a movement that does not exist, or
  /// asking for a set nobody could do. Not shown to the lifter — it is the
  /// number worth watching if a model starts drifting.
  final int dropped;

  bool get hasOptions => options.isNotEmpty;
}
