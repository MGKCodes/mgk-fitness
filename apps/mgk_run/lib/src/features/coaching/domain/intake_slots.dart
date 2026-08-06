import 'plan_shape.dart';

/// The onboarding slot state — **Dart owns this, the model never holds it**
/// (docs/architecture/onboarding.md). Each turn, the model returns extracted
/// slots which are [merge]d in; Dart decides what's missing and sanity-checks
/// the values. The model will happily accept 200 miles a week — Dart won't.
class IntakeSlots {
  const IntakeSlots({
    this.shape,
    this.commitments,
    this.goalDistanceMeters,
    this.eventDate,
    this.currentWeeklyMeters,
    this.longestRecentMeters,
    this.daysPerWeek,
    this.availableWeekdays,
    this.timeTrialDistanceMeters,
    this.timeTrialDuration,
    this.injuryNotes,
  });

  /// What kind of plan this runner is after. **The first thing intake
  /// establishes**, because it decides what else is worth asking: a runner
  /// keeping a rhythm has no race date, and asking for one is the app not
  /// listening (ADR-0011).
  ///
  /// The model proposes it; [resolvedShape] disposes.
  final PlanShape? shape;

  /// Sessions they repeat every week. The substance of a rhythm.
  final List<PlanCommitment>? commitments;

  final double? goalDistanceMeters;
  final DateTime? eventDate;
  final double? currentWeeklyMeters;
  final double? longestRecentMeters;
  final int? daysPerWeek;
  final Set<int>? availableWeekdays;
  final double? timeTrialDistanceMeters;
  final Duration? timeTrialDuration;
  final String? injuryNotes;

  /// The shape, as the *data* supports rather than as the model claimed.
  ///
  /// **The model proposes, Dart disposes** (ADR-0003), and a shape is exactly
  /// the kind of thing a model gets confidently wrong: told "I'd like to run a
  /// marathon one day" it will happily answer `block`, which then demands a date
  /// that does not exist. A claim of `block` with no date is a horizon; a claim
  /// of anything with no goal and no commitments is a log.
  PlanShape get resolvedShape {
    final claimed = shape;
    final hasGoal = goalDistanceMeters != null;
    final hasDate = eventDate != null;
    final hasRhythm = commitments?.isNotEmpty ?? false;

    // A claim can only be honoured if its own preconditions are met.
    if (claimed == PlanShape.block && hasGoal && hasDate) {
      return PlanShape.block;
    }
    if (claimed == PlanShape.horizon && hasGoal) return PlanShape.horizon;
    if (claimed == PlanShape.rhythm && (hasRhythm || daysPerWeek != null)) {
      return PlanShape.rhythm;
    }
    if (claimed == PlanShape.log) return PlanShape.log;

    // No usable claim: read it off the data.
    if (hasGoal && hasDate) return PlanShape.block;
    if (hasGoal) return PlanShape.horizon;
    if (hasRhythm || daysPerWeek != null) return PlanShape.rhythm;
    return PlanShape.log;
  }

  /// Required slots that are still empty, **for this runner's shape**
  /// (docs/architecture/onboarding.md).
  ///
  /// This list used to be the same for everybody and included the event date,
  /// which is why a runner who only wanted to run their local parkrun could
  /// never finish onboarding: `isComplete` could not return true, so the coach
  /// circled back to "when is your race?" until it hit the turn cap.
  Set<String> get missingRequired {
    // The shape being *asked about*, not the one the data supports. These differ
    // and both are right: a model that has correctly heard "I'm running Berlin"
    // claims a block before it has the date, and intake must go on to ask for
    // it. [resolvedShape] would call that a horizon and stop asking, which
    // would quietly drop the question the runner is waiting to answer.
    //
    // If the date never comes — "no race yet, I just want to run one" — the
    // model revises its claim to a horizon and this settles. The turn cap
    // catches a model that will not.
    return requiredSlots.where((slot) => !_isFilled(slot)).toSet();
  }

  /// Every slot this runner's shape needs, **filled or not**.
  ///
  /// The denominator [missingRequired] is the numerator of. Split out because
  /// the onboarding screen was dividing by a hardcoded 6 — the block count — so
  /// its progress bar was wrong for three shapes out of four, and a rhythm
  /// runner watched it stall at four sixths on a conversation that was
  /// finished (ADR-0011).
  ///
  /// It can *grow* as the shape settles: before the model has established what
  /// the runner is after there is one slot, the intent, and once it knows there
  /// are four or six. That is honest rather than awkward — a bar cannot know
  /// its own length before the conversation knows what it is asking about.
  Set<String> get requiredSlots {
    final shape = this.shape ?? resolvedShape;
    return <String>{
      // A shape has to be settled before anything else can be asked for.
      if (this.shape == null && shape == PlanShape.log) 'intent',

      if (shape.progresses) 'goal',
      if (shape == PlanShape.block) 'event_date',
      if (shape == PlanShape.rhythm) 'rhythm',

      if (shape.hasWeeks) ...<String>{
        'weekly_volume',
        'longest_run',
        'days_per_week',
        // A time trial buys pace bands. Worth having for a rhythm runner, but
        // not worth blocking them over — they came to keep turning up, not to
        // be assessed.
        if (shape.progresses) 'time_trial',
      },
    };
  }

  /// Whether [slot] has an answer in it yet.
  bool _isFilled(String slot) => switch (slot) {
    // Never filled where it is required: 'intent' is only asked for while the
    // shape is unknown, and knowing it removes the slot rather than fills it.
    'intent' => shape != null,
    'goal' => goalDistanceMeters != null,
    'event_date' => eventDate != null,
    // Either half answers it — a named commitment ("parkrun, Saturdays") or a
    // bare cadence.
    'rhythm' => (commitments?.isNotEmpty ?? false) || daysPerWeek != null,
    'weekly_volume' => currentWeeklyMeters != null,
    'longest_run' => longestRecentMeters != null,
    'days_per_week' => daysPerWeek != null,
    'time_trial' =>
      timeTrialDistanceMeters != null && timeTrialDuration != null,
    _ => true,
  };

  /// Overlays the non-null values of [extracted] onto this state.
  IntakeSlots merge(IntakeSlots extracted) => IntakeSlots(
    shape: extracted.shape ?? shape,
    commitments: extracted.commitments ?? commitments,
    goalDistanceMeters: extracted.goalDistanceMeters ?? goalDistanceMeters,
    eventDate: extracted.eventDate ?? eventDate,
    currentWeeklyMeters: extracted.currentWeeklyMeters ?? currentWeeklyMeters,
    longestRecentMeters: extracted.longestRecentMeters ?? longestRecentMeters,
    daysPerWeek: extracted.daysPerWeek ?? daysPerWeek,
    availableWeekdays: extracted.availableWeekdays ?? availableWeekdays,
    timeTrialDistanceMeters:
        extracted.timeTrialDistanceMeters ?? timeTrialDistanceMeters,
    timeTrialDuration: extracted.timeTrialDuration ?? timeTrialDuration,
    injuryNotes: extracted.injuryNotes ?? injuryNotes,
  );

  /// Deterministic sanity checks on the filled slots — the model proposes, Dart
  /// disposes. Empty slots are not flagged (that's [missingRequired]'s job).
  List<SlotIssue> sanityIssues(DateTime now) {
    final issues = <SlotIssue>[];

    final date = eventDate;
    if (date != null && !date.isAfter(now)) {
      issues.add(
        const SlotIssue('event_date', 'the event date must be in the future'),
      );
    }

    final weekly = currentWeeklyMeters;
    if (weekly != null && (weekly < 5000 || weekly > 250000)) {
      issues.add(
        SlotIssue(
          'weekly_volume',
          'weekly volume (${(weekly / 1000).round()} km) is outside a plausible range',
        ),
      );
    }

    final longest = longestRecentMeters;
    if (longest != null) {
      if (longest <= 0 || longest > 80000) {
        issues.add(
          const SlotIssue(
            'longest_run',
            'longest run is outside a plausible range',
          ),
        );
      } else if (weekly != null && longest > weekly) {
        issues.add(
          const SlotIssue('longest_run', 'longest run exceeds weekly volume'),
        );
      }
    }

    final days = daysPerWeek;
    if (days != null && (days < 1 || days > 7)) {
      issues.add(
        const SlotIssue(
          'days_per_week',
          'days per week must be between 1 and 7',
        ),
      );
    }
    final weekdays = availableWeekdays;
    if (days != null && weekdays != null && weekdays.length < days) {
      issues.add(
        const SlotIssue(
          'days_per_week',
          'fewer available weekdays than days per week',
        ),
      );
    }

    final ttDistance = timeTrialDistanceMeters;
    final ttDuration = timeTrialDuration;
    if (ttDistance != null && ttDuration != null) {
      if (ttDistance <= 0 || ttDuration.inSeconds <= 0) {
        issues.add(
          const SlotIssue('time_trial', 'the time trial must be positive'),
        );
      } else {
        final paceSecPerKm = ttDuration.inSeconds / (ttDistance / 1000);
        if (paceSecPerKm < 120 || paceSecPerKm > 720) {
          issues.add(
            const SlotIssue('time_trial', 'the time-trial pace is implausible'),
          );
        }
      }
    }

    final goal = goalDistanceMeters;
    if (goal != null && (goal < 1000 || goal > 200000)) {
      issues.add(
        const SlotIssue('goal', 'goal distance is outside a plausible range'),
      );
    }

    for (final c in commitments ?? const <PlanCommitment>[]) {
      if (c.weekday < 1 || c.weekday > 7) {
        issues.add(
          const SlotIssue('rhythm', 'a commitment falls on no weekday'),
        );
        break;
      }
      final distance = c.distanceMeters;
      if (distance != null && (distance <= 0 || distance > 200000)) {
        issues.add(
          const SlotIssue(
            'rhythm',
            'a commitment distance is outside a plausible range',
          ),
        );
        break;
      }
    }

    return issues;
  }

  /// Intake is done when every required slot is filled and nothing fails a
  /// sanity check. The conversation also has a turn cap on top of this.
  bool isComplete(DateTime now) =>
      missingRequired.isEmpty && sanityIssues(now).isEmpty;
}

/// A slot value that failed a sanity check — surfaced on the editable
/// confirmation screen so the user can fix a bad extraction.
class SlotIssue {
  const SlotIssue(this.slot, this.message);

  final String slot;
  final String message;

  @override
  String toString() => '$slot: $message';
}
