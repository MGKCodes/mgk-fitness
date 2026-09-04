import 'dart:math' as math;

import 'plan_shape.dart';
import 'prescribed_distance.dart';
import 'runner_profile.dart';
import 'training_plan.dart';

/// A single broken invariant.
class Violation {
  const Violation(this.code, this.message);

  /// Stable machine code (e.g. `volume_ramp`) — fed back to the model on a
  /// regeneration attempt, and asserted in tests.
  final String code;
  final String message;

  @override
  String toString() => '[$code] $message';
}

/// The outcome of validating a skeleton or a week.
class ValidationResult {
  const ValidationResult(this.violations);

  final List<Violation> violations;

  bool get isValid => violations.isEmpty;

  bool has(String code) => violations.any((v) => v.code == code);
}

/// Tunable thresholds for the plan invariants. Precision isn't the point —
/// structure is — so these have generous tolerances.
class PlanRules {
  const PlanRules({
    this.maxWeeklyRampFraction = 0.10,
    this.deloadMaxFraction = 0.75,
    this.maxWeeksBetweenDeloads = 4,
    this.longRunMaxFraction = 0.40,
    this.longRunCeilingMeters = 38000,
    this.week1Tolerance = 0.20,
    this.weekVolumeTolerance = 0.15,
    this.longRunTolerance = 0.05,
    this.requireExactSessionCount = true,
    this.requireTaper = true,
    this.requireDeloadCadence = true,
    this.rejectPastDays = true,
  });

  /// Whether a session may fall on a day that has already gone.
  ///
  /// True while a plan is being *generated*, false while a runner is adapting
  /// one they are already living in. See [PlanRules.adaptation].
  final bool rejectPastDays;

  /// The rules for a change the **runner asked for**.
  ///
  /// The tight tolerances exist to catch a model that quietly ignored the plan.
  /// They are wrong for a runner who is deviating on purpose — a sore calf is a
  /// better reason to cut a long run than the plan is to keep it, and refusing
  /// that would make the coach useless exactly when it matters.
  ///
  /// So a sanctioned deviation still has to be a *structurally sound week* —
  /// no back-to-back hard days, nothing on an unavailable day, no long run over
  /// the ceiling — but it is allowed to depart from the slot it came from.
  /// Everything that protects the runner stays; only the fidelity-to-plan
  /// checks relax.
  const PlanRules.adaptation()
    : maxWeeklyRampFraction = 0.10,
      deloadMaxFraction = 0.75,
      maxWeeksBetweenDeloads = 4,
      longRunMaxFraction = 0.40,
      longRunCeilingMeters = 38000,
      week1Tolerance = 0.20,
      // A runner cutting a session should not be told their week no longer
      // matches a plan they are deliberately changing.
      weekVolumeTolerance = 0.60,
      longRunTolerance = 0.60,
      // Dropping a session is the runner's call — "I can only get out three
      // times this week" is a fact, not a violation. Adding one they have no
      // day for still is, so the check becomes a ceiling rather than an equals.
      requireExactSessionCount = false,
      requireTaper = true,
      requireDeloadCadence = true,
      // **Off for an adaptation, and this is load-bearing.** A runner adjusting
      // on Thursday is holding a week that already contains Monday, and telling
      // them Monday is in the past would refuse every mid-week change they
      // could possibly make.
      rejectPastDays = false;

  /// The rules for a plan that **holds a level** rather than climbing to one —
  /// a [PlanShape.rhythm].
  ///
  /// Almost every invariant in this file is about progression: ramp caps,
  /// deload cadence, a taper at the end. None of them mean anything for "5 km
  /// every Saturday", and applied to it they reject a perfectly good plan —
  /// there is no peak to deload from and no date to taper into. What survives
  /// is what protects the runner: the long run stays a sane fraction of the
  /// week, sessions land on days they are free, hard days do not stack.
  const PlanRules.rhythm()
    : maxWeeklyRampFraction = 0.10,
      deloadMaxFraction = 0.75,
      maxWeeksBetweenDeloads = 4,
      longRunMaxFraction = 0.40,
      longRunCeilingMeters = 38000,
      week1Tolerance = 0.20,
      weekVolumeTolerance = 0.25,
      longRunTolerance = 0.40,
      requireExactSessionCount = false,
      requireTaper = false,
      requireDeloadCadence = false,
      rejectPastDays = true;

  /// The rules for a [PlanShape.horizon] — ramps like a block, with nothing to
  /// taper into.
  const PlanRules.horizon()
    : maxWeeklyRampFraction = 0.10,
      deloadMaxFraction = 0.75,
      maxWeeksBetweenDeloads = 4,
      longRunMaxFraction = 0.40,
      longRunCeilingMeters = 38000,
      week1Tolerance = 0.20,
      weekVolumeTolerance = 0.15,
      longRunTolerance = 0.05,
      requireExactSessionCount = true,
      requireTaper = false,
      requireDeloadCadence = true,
      rejectPastDays = true;

  /// The rule set for [shape]. The one place the mapping lives, so a new shape
  /// is a compile error here rather than a silently-wrong validation.
  factory PlanRules.forShape(PlanShape shape) => switch (shape) {
    PlanShape.block => const PlanRules(),
    PlanShape.horizon => const PlanRules.horizon(),
    PlanShape.rhythm || PlanShape.log => const PlanRules.rhythm(),
  };

  final double maxWeeklyRampFraction;
  final double deloadMaxFraction;
  final int maxWeeksBetweenDeloads;
  final double longRunMaxFraction;
  final double longRunCeilingMeters;
  final double week1Tolerance;
  final double weekVolumeTolerance;

  /// Whether a week must contain exactly [RunnerProfile.daysPerWeek] sessions.
  ///
  /// True when generating: a plan that quietly drops a day is a broken plan.
  /// False when adapting: the runner is allowed to do less than they planned.
  final bool requireExactSessionCount;

  /// How far a generated week's long run may drift from the long run its
  /// skeleton slot declares. Tighter than [weekVolumeTolerance] because the
  /// slot's long run is shown to the runner on the plan arc as a single number,
  /// so drift here reads as two screens contradicting each other. Floored at
  /// [prescribedGridSlackMeters] where it is applied, since the week rounds to
  /// whole kilometres and the slot does not.
  final double longRunTolerance;

  /// Whether the final week must be a taper below peak. Only a block has an
  /// endpoint; a taper without a date is a guess about a race nobody entered.
  final bool requireTaper;

  /// Whether a deload is required every [maxWeeksBetweenDeloads] weeks. A plan
  /// that never climbs has nothing to back off from.
  final bool requireDeloadCadence;
}

/// Validates the skeleton (the arc) against the runner's profile.
///
/// **The model proposes, the validator disposes** — long-horizon generation
/// degrades structurally in ways invisible on inspection, so every invariant is
/// checked here.
ValidationResult validateSkeleton(
  PlanSkeleton skeleton,
  RunnerProfile profile, {
  PlanRules rules = const PlanRules(),
}) {
  final v = <Violation>[];
  final weeks = skeleton.weeks;
  if (weeks.isEmpty) {
    return const ValidationResult(<Violation>[
      Violation('empty', 'skeleton has no weeks'),
    ]);
  }

  // Week 1 close to the runner's stated current volume.
  final week1 = weeks.first.volumeMeters;
  if ((week1 - profile.currentWeeklyMeters).abs() >
      profile.currentWeeklyMeters * rules.week1Tolerance) {
    v.add(
      Violation(
        'week1_volume',
        'week 1 (${week1.round()} m) is not within '
            '${(rules.week1Tolerance * 100).round()}% of current '
            '${profile.currentWeeklyMeters.round()} m',
      ),
    );
  }

  for (var i = 1; i < weeks.length; i++) {
    final prev = weeks[i - 1];
    final cur = weeks[i];

    // Deload weeks drop volume rather than ramp.
    if (cur.isDeload) {
      if (cur.volumeMeters > prev.volumeMeters * rules.deloadMaxFraction) {
        v.add(
          Violation(
            'deload_volume',
            'deload week ${cur.index} (${cur.volumeMeters.round()} m) is not '
                '<= ${(rules.deloadMaxFraction * 100).round()}% of the prior '
                '${prev.volumeMeters.round()} m',
          ),
        );
      }
      continue;
    }

    // The first week back from a deload may jump back up.
    if (prev.isDeload) continue;

    // Otherwise the weekly ramp is capped (a small absolute slack avoids
    // false positives on rounding).
    if (cur.volumeMeters >
        prev.volumeMeters * (1 + rules.maxWeeklyRampFraction) + 1) {
      v.add(
        Violation(
          'volume_ramp',
          'week ${cur.index} ramps > ${(rules.maxWeeklyRampFraction * 100).round()}% '
              '(${prev.volumeMeters.round()} -> ${cur.volumeMeters.round()} m)',
        ),
      );
    }
  }

  // A deload at least every N weeks (only meaningful for longer plans, and
  // only for plans that climb at all).
  if (rules.requireDeloadCadence &&
      weeks.length > rules.maxWeeksBetweenDeloads) {
    var sinceDeload = 0;
    for (final w in weeks) {
      sinceDeload = w.isDeload ? 0 : sinceDeload + 1;
      if (sinceDeload > rules.maxWeeksBetweenDeloads) {
        v.add(
          Violation(
            'deload_cadence',
            'more than ${rules.maxWeeksBetweenDeloads} weeks without a deload by '
                'week ${w.index}',
          ),
        );
        break;
      }
    }
  }

  // A taper at the end: the final week is a taper phase, below peak volume.
  // Skipped where there is nothing to taper into.
  if (rules.requireTaper) {
    final peak = weeks
        .map((w) => w.volumeMeters)
        .reduce((a, b) => a > b ? a : b);
    final last = weeks.last;
    if (last.phase != Phase.taper) {
      v.add(
        Violation(
          'taper_missing',
          'final week ${last.index} is ${last.phase.name}, not a taper',
        ),
      );
    }
    if (last.volumeMeters >= peak) {
      v.add(
        Violation(
          'taper_volume',
          'final week (${last.volumeMeters.round()} m) is not below peak '
              '(${peak.round()} m)',
        ),
      );
    }
  }

  _checkLongRuns(weeks, rules, v);

  return ValidationResult(v);
}

/// Validates a generated week against its skeleton [slot] and the profile.
ValidationResult validateWeek(
  TrainingWeek week,
  SkeletonWeek slot,
  RunnerProfile profile, {
  PlanRules rules = const PlanRules(),
  DateTime? weekStart,
  DateTime? now,
}) {
  final v = <Violation>[];
  final runs = week.runs.toList();

  // Session count against the runner's stated days per week. Exact when
  // generating; a ceiling when the runner is adapting their own week.
  final tooMany = runs.length > profile.daysPerWeek;
  if (rules.requireExactSessionCount
      ? runs.length != profile.daysPerWeek
      : tooMany) {
    v.add(
      Violation(
        'session_count',
        '${runs.length} run days '
            '${tooMany ? 'exceeds' : 'does not match'} '
            'the ${profile.daysPerWeek} available',
      ),
    );
  }

  // Sessions only on days the runner said they're available. Every session, not
  // just the runs: a strength day the runner cannot make is as wrong as a run
  // they cannot make.
  for (final s in week.sessions) {
    if (s.kind == SessionKind.rest) continue;
    if (!profile.availableWeekdays.contains(s.weekday)) {
      v.add(
        Violation(
          'unavailable_day',
          'a session falls on weekday ${s.weekday}, which is not available',
        ),
      );
    }
  }

  // **The two date rules, and the only ones in this file.**
  //
  // Everything else here is about shape -- volume, ramp, spacing -- and none of
  // it has ever needed a calendar. That was the gap: a plan generated on a
  // Friday put the current week's sessions on the Tuesday, Wednesday and
  // Thursday that had already gone, and the final week prescribed a 5 km run on
  // race day itself. Both passed every check, because no check could see a
  // date.
  //
  // They are opt-in through [weekStart] rather than mandatory, because the plan
  // model deliberately carries no dates at all -- a [PlannedSession] knows only
  // its weekday, and dates are reattached by [StoredPlan] at read time. The
  // caller that has the calendar passes it; the many that do not are unchanged.
  if (weekStart != null) {
    final DateTime start = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    );
    final DateTime? today = now == null
        ? null
        : DateTime(now.year, now.month, now.day);
    final DateTime? race = profile.eventDate == null
        ? null
        : DateTime(
            profile.eventDate!.year,
            profile.eventDate!.month,
            profile.eventDate!.day,
          );

    for (final s in week.sessions) {
      if (s.kind == SessionKind.rest) continue;
      final DateTime on = start.add(Duration(days: s.weekday - 1));

      // A day that has gone cannot be trained, and a plan that opens by
      // prescribing three of them starts life owing the runner an apology.
      if (rules.rejectPastDays && today != null && on.isBefore(today)) {
        v.add(
          Violation(
            'session_in_the_past',
            'a session falls on weekday ${s.weekday}, which was '
                '${today.difference(on).inDays} day(s) ago',
          ),
        );
      }

      // **Race day is the event, not a training day** (ADR-0027). The whole
      // block is built to arrive at it, and the deterministic builder puts the
      // long run on the latest available weekday -- which in the final week is
      // usually the Sunday the race is on.
      if (race != null && on.isAtSameMomentAs(race)) {
        v.add(
          Violation(
            'session_on_race_day',
            'a ${s.kind.name} session falls on race day, which is the event',
          ),
        );
      }
    }
  }

  // Strength is a session, not a run. A distance on one would land in the weekly
  // total and could be picked as the long run — so it is refused rather than
  // quietly zeroed, because a model that put 8 km on a gym session has
  // misunderstood the week, not made a typo.
  final strength = week.support.toList();
  for (final s in strength) {
    if (s.distanceMeters > 0) {
      v.add(
        Violation(
          'strength_distance',
          'a strength session carries ${s.distanceMeters.round()} m; strength '
              'work adds no running volume',
        ),
      );
      break;
    }
  }
  if (strength.length > profile.strengthDaysPerWeek) {
    v.add(
      Violation(
        'strength_count',
        '${strength.length} strength days exceeds the '
            '${profile.strengthDaysPerWeek} the runner asked for',
      ),
    );
  }

  // Never two hard sessions on consecutive days.
  final hardDays = <int>[
    for (final s in runs)
      if (s.kind.isHard) s.weekday,
  ]..sort();
  for (var i = 1; i < hardDays.length; i++) {
    if (hardDays[i] - hardDays[i - 1] == 1) {
      v.add(
        Violation(
          'back_to_back_hard',
          'hard sessions on consecutive days (${hardDays[i - 1]} & ${hardDays[i]})',
        ),
      );
      break;
    }
  }

  // Long run within a sane fraction of the week, and under the absolute ceiling.
  if (week.longRunMeters > week.volumeMeters * rules.longRunMaxFraction + 1) {
    v.add(
      Violation(
        'long_run_fraction',
        'long run (${week.longRunMeters.round()} m) exceeds '
            '${(rules.longRunMaxFraction * 100).round()}% of weekly volume',
      ),
    );
  }
  if (week.longRunMeters > rules.longRunCeilingMeters) {
    v.add(
      Violation(
        'long_run_ceiling',
        'long run (${week.longRunMeters.round()} m) exceeds the ceiling',
      ),
    );
  }

  // Weekly volume tracks the skeleton slot it was generated for.
  if (slot.volumeMeters > 0 &&
      (week.volumeMeters - slot.volumeMeters).abs() >
          slot.volumeMeters * rules.weekVolumeTolerance) {
    v.add(
      Violation(
        'week_volume',
        'week volume (${week.volumeMeters.round()} m) is not within '
            '${(rules.weekVolumeTolerance * 100).round()}% of the slot '
            '(${slot.volumeMeters.round()} m)',
      ),
    );
  }

  // The long run tracks the slot's too. The plan arc shows the slot's long run,
  // so a week that quietly picks its own contradicts what the runner was shown
  // for that very week — checked separately from the fraction/ceiling bounds
  // above, which a divergent long run can satisfy perfectly well.
  //
  // Floored at half a kilometre because the week prescribes on the whole-
  // kilometre grid while the slot keeps the plan's exact working, so the two
  // legitimately differ by up to that much. Without the floor a 5.7 km slot
  // prescribed as 6 km is 330 m out against a 285 m band, and the app rejects
  // its own arithmetic — a rounding reported as a contradiction.
  final longRunBand = math.max(
    slot.longRunMeters * rules.longRunTolerance,
    prescribedGridSlackMeters,
  );
  if (slot.longRunMeters > 0 &&
      (week.longRunMeters - slot.longRunMeters).abs() > longRunBand) {
    v.add(
      Violation(
        'long_run_slot',
        'long run (${week.longRunMeters.round()} m) is not within '
            '${(rules.longRunTolerance * 100).round()}% of the slot '
            '(${slot.longRunMeters.round()} m)',
      ),
    );
  }

  return ValidationResult(v);
}

void _checkLongRuns(
  List<SkeletonWeek> weeks,
  PlanRules rules,
  List<Violation> v,
) {
  for (final w in weeks) {
    if (w.longRunMeters > w.volumeMeters * rules.longRunMaxFraction + 1) {
      v.add(
        Violation(
          'long_run_fraction',
          'week ${w.index} long run (${w.longRunMeters.round()} m) exceeds '
              '${(rules.longRunMaxFraction * 100).round()}% of volume',
        ),
      );
    }
    if (w.longRunMeters > rules.longRunCeilingMeters) {
      v.add(
        Violation(
          'long_run_ceiling',
          'week ${w.index} long run (${w.longRunMeters.round()} m) exceeds the '
              'ceiling',
        ),
      );
    }
  }
}
