import 'plan_shape.dart';

/// The structured runner profile a plan is built on — the validated output of
/// onboarding (docs/architecture/onboarding.md). All distances are metric.
///
/// The model proposes these values during the intake conversation; Dart
/// sanity-checks them before they become a profile (future event date,
/// plausible volume, parseable time trial).
class RunnerProfile {
  const RunnerProfile({
    this.goalDistanceMeters,
    this.eventDate,
    required this.currentWeeklyMeters,
    required this.longestRecentMeters,
    required this.daysPerWeek,
    required this.availableWeekdays,
    this.commitments = const <PlanCommitment>[],
    this.strengthDaysPerWeek = 0,
    this.timeTrialDistanceMeters,
    this.timeTrialDuration,
    this.injuryNotes,
  });

  /// The goal race distance in meters (e.g. 42195 for a marathon).
  ///
  /// **Null is a real answer**, not missing data: a runner keeping a rhythm is
  /// not training toward a distance. See
  /// [ADR-0011](../../../../../docs/decisions/0011-a-plan-has-a-shape.md).
  final double? goalDistanceMeters;

  /// The date of the event, when there is one.
  ///
  /// Null with a goal set means [PlanShape.horizon] — a distance to reach with
  /// no race entered — and is why there is nothing to taper into. This was
  /// required of every runner for no reason anyone had chosen, which is what
  /// ADR-0011 records.
  final DateTime? eventDate;
  final double currentWeeklyMeters;
  final double longestRecentMeters;

  /// Days a week the runner **runs**. Strength days are counted separately, so
  /// adding one never costs a run.
  final int daysPerWeek;

  /// Weekdays the runner can train, as `DateTime.monday`..`DateTime.sunday`.
  final Set<int> availableWeekdays;

  /// Sessions the runner repeats every week — the substance of a
  /// [PlanShape.rhythm]. Empty for a block or a horizon, whose weeks come from
  /// the skeleton instead.
  final List<PlanCommitment> commitments;

  /// Strength sessions a week, on top of the runs. Zero by default: a runner who
  /// never said they lift should not find a gym session in their plan.
  final int strengthDaysPerWeek;

  /// A recent race or time trial, the single input to pace derivation.
  final double? timeTrialDistanceMeters;
  final Duration? timeTrialDuration;

  final String? injuryNotes;

  /// A copy with some fields replaced.
  ///
  /// The `clear` flags exist because three of these fields treat null as a real
  /// answer rather than as "unchanged" (ADR-0011). Without them a runner
  /// stepping off a block could never be expressed: passing
  /// `goalDistanceMeters: null` is indistinguishable from not passing it, so
  /// the old marathon would quietly survive the change that was meant to end
  /// it. Saying so explicitly is uglier and cannot go wrong silently.
  RunnerProfile copyWith({
    double? goalDistanceMeters,
    DateTime? eventDate,
    double? currentWeeklyMeters,
    double? longestRecentMeters,
    int? daysPerWeek,
    Set<int>? availableWeekdays,
    List<PlanCommitment>? commitments,
    int? strengthDaysPerWeek,
    double? timeTrialDistanceMeters,
    Duration? timeTrialDuration,
    String? injuryNotes,
    bool clearGoalDistance = false,
    bool clearEventDate = false,
    bool clearInjuryNotes = false,
  }) => RunnerProfile(
    goalDistanceMeters: clearGoalDistance
        ? null
        : (goalDistanceMeters ?? this.goalDistanceMeters),
    eventDate: clearEventDate ? null : (eventDate ?? this.eventDate),
    currentWeeklyMeters: currentWeeklyMeters ?? this.currentWeeklyMeters,
    longestRecentMeters: longestRecentMeters ?? this.longestRecentMeters,
    daysPerWeek: daysPerWeek ?? this.daysPerWeek,
    availableWeekdays: availableWeekdays ?? this.availableWeekdays,
    commitments: commitments ?? this.commitments,
    strengthDaysPerWeek: strengthDaysPerWeek ?? this.strengthDaysPerWeek,
    timeTrialDistanceMeters:
        timeTrialDistanceMeters ?? this.timeTrialDistanceMeters,
    timeTrialDuration: timeTrialDuration ?? this.timeTrialDuration,
    injuryNotes: clearInjuryNotes ? null : (injuryNotes ?? this.injuryNotes),
  );
}
