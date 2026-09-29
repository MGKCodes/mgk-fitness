/// A change to what the runner is training *for*, and the checks it has to pass
/// before it rebuilds their plan.
///
/// Pure and testable for the same reason [RunDraft] is (ADR-0016): it has two
/// callers of very different trustworthiness. One day it will be a form. Today
/// it is the coach, reading "I've entered the Manchester Marathon on 5 April"
/// out of a sentence — the model proposing, so Dart has to dispose (CLAUDE.md
/// rule 2, ADR-0003).
///
/// **This is the most destructive thing the coach can propose.** A new goal or
/// a new date does not edit the plan, it replaces it: the skeleton is derived
/// from the profile, so changing the target supersedes the block the runner has
/// been working through and every week in it. A misheard date is not a typo in
/// a log, it is sixteen weeks of training thrown away. Hence a validator that
/// refuses rather than repairs, and a confirmation that says plainly what is
/// about to be lost.
///
/// Metric throughout — km only exist at the display layer (CLAUDE.md rule 4).
library;

import 'plan_shape.dart';
import 'runner_profile.dart';
import 'stored_plan.dart';

/// One thing wrong with a goal, named by the field it belongs to. Mirrors
/// [RunIssue] and `SlotIssue`.
class GoalIssue {
  const GoalIssue(this.field, this.message);

  final String field;
  final String message;

  @override
  String toString() => '$field: $message';
}

/// Thrown when a caller tries to apply a goal that does not pass [GoalDraft
/// .issues], so a bad target cannot reach a plan by anyone forgetting to look.
class GoalDraftInvalid implements Exception {
  const GoalDraftInvalid(this.issues);

  final List<GoalIssue> issues;

  @override
  String toString() => 'GoalDraftInvalid: ${issues.join('; ')}';
}

/// The shortest sensible race. Below this it is a parkrun distance at most, and
/// a "goal" of 500 m is a misheard number rather than an ambition.
const double kMinGoalMeters = 1000;

/// Beyond this Runio is not the right tool. The plan builder derives volume from
/// the goal, and a 500 km target produces an arc no validator should bless.
const double kMaxGoalMeters = 100000;

/// The least notice worth building a block on.
///
/// Not a judgement about whether they can finish — people run races off no
/// training and that is their business. It is that a plan cannot *do* anything
/// in under a week: there is no ramp, no deload and no taper to place, so what
/// comes back would be a plan-shaped object rather than a plan.
const int kMinDaysToRace = 7;

/// The furthest ahead a block is worth generating. Past this the plan is
/// fiction — fitness, life and intent all move — and the weeks would be
/// regenerated long before the runner reached them.
const int kMaxDaysToRace = 730;

/// A proposed change to the runner's target, before anything is rebuilt.
///
/// Both fields nullable, and the combinations are the plan shapes of ADR-0011
/// rather than degrees of completeness:
///
/// - distance **and** date → a block, counting down to something
/// - distance, no date → a horizon: ramping toward a distance with nothing to
///   taper into
/// - neither → the runner is stepping off a block. Legal, and it is how
///   "actually I just want to keep ticking over" is expressed.
///
/// A date with no distance is the one combination that is not a shape, because
/// a date alone says nothing about what to train for.
class GoalDraft {
  const GoalDraft({this.goalDistanceMeters, this.eventDate});

  /// The target distance in meters, or null for no distance goal.
  final double? goalDistanceMeters;

  /// Race day, or null when there is no race.
  final DateTime? eventDate;

  /// Reads a draft off the runner's current profile, so a change the coach
  /// proposes starts from what is already true rather than from nothing. A
  /// runner who says "make it the 12th of April" is moving their existing race,
  /// not entering a distanceless one.
  factory GoalDraft.from(RunnerProfile profile) => GoalDraft(
    goalDistanceMeters: profile.goalDistanceMeters,
    eventDate: profile.eventDate,
  );

  GoalDraft copyWith({
    double? goalDistanceMeters,
    DateTime? eventDate,
    bool clearDistance = false,
    bool clearDate = false,
  }) => GoalDraft(
    goalDistanceMeters: clearDistance
        ? null
        : (goalDistanceMeters ?? this.goalDistanceMeters),
    eventDate: clearDate ? null : (eventDate ?? this.eventDate),
  );

  /// The plan shape this target implies (ADR-0011).
  PlanShape get shape {
    if (goalDistanceMeters == null) return PlanShape.rhythm;
    return eventDate == null ? PlanShape.horizon : PlanShape.block;
  }

  /// Everything wrong with it, judged against [now]. Empty means it may be
  /// applied.
  ///
  /// Order matters: the distance is checked before the date, because a runner
  /// reading one problem should read the one nearest the start of the sentence
  /// they said.
  List<GoalIssue> issues(DateTime now) {
    final out = <GoalIssue>[];
    final distance = goalDistanceMeters;
    final date = eventDate;

    if (distance != null) {
      if (!distance.isFinite || distance <= 0) {
        out.add(const GoalIssue('goal', 'A distance has to be a real number.'));
      } else if (distance < kMinGoalMeters) {
        out.add(
          GoalIssue(
            'goal',
            'That is under ${(kMinGoalMeters / 1000).round()} km, which is too '
                'short to build a plan around.',
          ),
        );
      } else if (distance > kMaxGoalMeters) {
        out.add(
          GoalIssue(
            'goal',
            'That is over ${(kMaxGoalMeters / 1000).round()} km. The app does not '
                'plan ultras.',
          ),
        );
      }
    }

    if (date != null) {
      // A date on its own is not a plan shape: there is nothing to train for.
      if (distance == null) {
        out.add(
          const GoalIssue(
            'event',
            'A race needs a distance as well as a date.',
          ),
        );
      }
      final days = _daysBetween(now, date);
      if (days < 0) {
        out.add(const GoalIssue('event', 'That date has already passed.'));
      } else if (days < kMinDaysToRace) {
        out.add(
          GoalIssue(
            'event',
            'That is under $kMinDaysToRace days away, which is too soon to '
                'build a block around.',
          ),
        );
      } else if (days > kMaxDaysToRace) {
        out.add(
          GoalIssue(
            'event',
            'That is more than ${(kMaxDaysToRace / 365).round()} years away. '
                'Come back when it is closer.',
          ),
        );
      }
    }

    return out;
  }

  bool isValid(DateTime now) => issues(now).isEmpty;

  /// True when this would actually change [profile]. A proposal that changes
  /// nothing must never be offered: it would ask the runner to approve throwing
  /// away their block in exchange for the block they already have.
  bool changes(RunnerProfile profile) =>
      goalDistanceMeters != profile.goalDistanceMeters ||
      !_sameDay(eventDate, profile.eventDate);

  /// [profile] with this target on it. The rest of the runner — their days,
  /// their volume, their time trial — is untouched, because none of it is what
  /// they were changing.
  RunnerProfile onto(RunnerProfile profile) => profile.copyWith(
    goalDistanceMeters: goalDistanceMeters,
    eventDate: eventDate,
    clearGoalDistance: goalDistanceMeters == null,
    clearEventDate: eventDate == null,
  );

  // DST-safe (see stored_plan.dart's daysBetweenDates): a race entered right
  // at the spring or autumn change used to be counted a day short by a plain
  // `Duration` difference between two local midnights.
  static int _daysBetween(DateTime from, DateTime to) =>
      daysBetweenDates(from, to);

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
