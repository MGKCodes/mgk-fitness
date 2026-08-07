import 'package:meta/meta.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../stats/domain/training_stats.dart';
import '../../tracking/data/exercise_lookup.dart';
import '../../tracking/domain/session.dart';
import 'plan_proposal.dart';

/// Turns a week the coach proposed into one the app will show, or into a list
/// of reasons it will not.
///
/// **This is where "targets come from your own numbers" stops being a sentence
/// and starts being enforced.** Two jobs, and the second is the one that
/// matters:
///
///   1. Check the shape — the right number of sessions, on days the lifter
///      said they train, with sets and reps a person could do.
///   2. **Work out every weight.** The coach prescribes an intensity; the
///      kilograms come from this lifter's own logged sets, or they do not come
///      at all.
///
/// A rejected week is not a dead end. `violations` is written to be handed
/// straight back to the generator, which is why each one names the session and
/// says what to do rather than what went wrong — the same shape Run's plan
/// validator uses, for the same reason.
@immutable
class PlanValidator {
  const PlanValidator({ExerciseLookup? lookup, this.roundingKg = 2.5})
    : _lookup = lookup;

  final ExerciseLookup? _lookup;

  /// What a weight is rounded to.
  ///
  /// 2.5 kg is the smallest change most people can actually make to a barbell —
  /// a 1.25 kg plate on each side. A target of 84.7 kg is not a target, it is a
  /// number nobody can load, and it makes the whole plan read as generated.
  final double roundingKg;

  /// Checks a proposed week against what this lifter can do, and resolves its
  /// targets from their log.
  WeekVerdict check(
    WeekProposal proposal, {
    required PlanProfile profile,
    required List<Session> log,
  }) {
    final lookup = _lookup ?? ExerciseLookup();
    final violations = <String>[];

    if (proposal.sessions.length != profile.daysPerWeek) {
      violations.add(
        'Give exactly ${profile.daysPerWeek} sessions; '
        'this week has ${proposal.sessions.length}.',
      );
    }

    final seen = <int>{};
    for (final session in proposal.sessions) {
      final day = _weekdayName(session.weekday);

      if (!profile.availableWeekdays.contains(session.weekday)) {
        violations.add(
          'Move the $day session: they only train on '
          '${profile.availableWeekdays.map(_weekdayName).join(', ')}.',
        );
      }
      if (!seen.add(session.weekday)) {
        violations.add('Only one session on $day.');
      }
      if (session.rationale.isEmpty) {
        violations.add('Say why the $day session looks like this.');
      }
      if (session.movements.isEmpty) {
        violations.add('The $day session has no movements.');
      }

      for (final movement in session.movements) {
        final where =
            '$day, ${movement.name.isEmpty ? 'a movement' : movement.name}';

        if (movement.name.isEmpty) {
          violations.add('$where: every movement needs a name.');
        } else if (lookup.find(movement.name) == null) {
          // Not fatal to the lifter — they can log anything — but the coach
          // should prescribe movements the app can illustrate and categorise,
          // and an unresolvable name is usually a model inventing a variation.
          violations.add(
            '$where is not a movement this app knows. Use its usual name.',
          );
        }
        if (movement.sets < 1 || movement.sets > 10) {
          violations.add('$where: sets must be between 1 and 10.');
        }
        if (movement.reps < 1 || movement.reps > 20) {
          violations.add('$where: reps must be between 1 and 20.');
        }

        final pct = movement.intensityPct;
        if (pct != null) {
          if (pct < 40 || pct > 100) {
            violations.add(
              '$where: intensity must be between 40 and 100 percent, or null.',
            );
          }
          // The one rule about the training rather than the shape. A deload
          // that is only lighter in the intent sentence is not a deload, and
          // the whole point of the phase is that the week after it can be hard.
          if (profile.isDeload && pct > _deloadCeilingPct) {
            violations.add(
              '$where: this is a deload week, so nothing above '
              '$_deloadCeilingPct percent.',
            );
          }
          if (!_intensitySuitsReps(pct, movement.reps)) {
            violations.add(
              '$where: ${movement.reps} reps at $pct percent is not a set. '
              'Either lower the intensity or cut the reps.',
            );
          }
        }
      }
    }

    if (violations.isNotEmpty) return WeekVerdict.rejected(violations);

    return WeekVerdict.accepted(<PlannedSession>[
      for (final session in proposal.sessions)
        PlannedSession(
          weekday: session.weekday,
          kind: session.kind,
          rationale: session.rationale,
          movements: <PlannedMovement>[
            for (final movement in session.movements)
              PlannedMovement(
                name: movement.name,
                sets: movement.sets,
                reps: movement.reps,
                note: movement.note,
                target: _target(movement, log),
              ),
          ],
        ),
    ]);
  }

  /// Grades a mid-session substitution.
  ///
  /// **Unusable options are dropped, not rejected.** A week that breaks a rule
  /// goes back to the generator, because there is time and the lifter is not
  /// waiting. A swap is asked for by somebody standing between sets, so the
  /// trade goes the other way: keep whatever survives, discard the rest, and
  /// always show the reply. Coming back with an error because the second of
  /// three suggestions named a movement that does not exist would be the worst
  /// possible reading of "the validator disposes".
  ///
  /// Targets are derived exactly as they are for a planned week — and here they
  /// are usually null, because a substitute is typically something they have
  /// not done before.
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

  /// Nothing above this in a deload week.
  static const int _deloadCeilingPct = 70;

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

  static String _weekdayName(int weekday) => switch (weekday) {
    1 => 'Monday',
    2 => 'Tuesday',
    3 => 'Wednesday',
    4 => 'Thursday',
    5 => 'Friday',
    6 => 'Saturday',
    7 => 'Sunday',
    _ => 'day $weekday',
  };
}

/// What the lifter can do, as the plan recorded it.
@immutable
class PlanProfile {
  const PlanProfile({
    required this.daysPerWeek,
    required this.availableWeekdays,
    this.isDeload = false,
  });

  final int daysPerWeek;

  /// 1 = Monday through 7 = Sunday.
  final List<int> availableWeekdays;

  /// Whether the week being checked is a deload.
  final bool isDeload;
}

/// A checked week, or the reasons there is not one.
@immutable
class WeekVerdict {
  const WeekVerdict._({required this.sessions, required this.violations});

  factory WeekVerdict.accepted(List<PlannedSession> sessions) =>
      WeekVerdict._(sessions: sessions, violations: const <String>[]);

  factory WeekVerdict.rejected(List<String> violations) =>
      WeekVerdict._(sessions: const <PlannedSession>[], violations: violations);

  final List<PlannedSession> sessions;

  /// Written to be sent straight back to the generator as its next attempt's
  /// brief, so each one says what to do rather than what went wrong.
  final List<String> violations;

  bool get isAccepted => violations.isEmpty;
}

@immutable
class PlannedSession {
  const PlannedSession({
    required this.weekday,
    required this.kind,
    required this.movements,
    required this.rationale,
  });

  final int weekday;
  final String kind;
  final List<PlannedMovement> movements;
  final String rationale;
}

@immutable
class PlannedMovement {
  const PlannedMovement({
    required this.name,
    required this.sets,
    required this.reps,
    this.target,
    this.note,
  });

  final String name;
  final int sets;
  final int reps;

  /// Derived here from the lifter's own log — never read from the model, which
  /// has nowhere to put one. Null means "no number worth giving", which is a
  /// prescription rather than a gap.
  final Mass? target;

  final String? note;
}

/// A graded substitution: what the coach said, and whatever it offered that
/// survived checking.
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
