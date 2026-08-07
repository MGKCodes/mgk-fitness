import 'package:meta/meta.dart';

import '../../tracking/domain/session.dart';
import 'plan.dart';
import 'plan_proposal.dart';
import 'plan_validator.dart';

/// The coach, as the planner needs it. Implemented against the Edge Function;
/// faked in tests and the preview harness.
abstract interface class CoachPlanner {
  /// One turn of the intake conversation.
  Future<IntakeTurn> intake({
    required PlanIntake known,
    required List<PlannerTurn> history,
  });

  /// The block's arc: what each week is for.
  Future<List<PlanWeek>> skeleton({
    required PlanIntake intake,
    List<String> violations,
  });

  /// One week's sessions, unvalidated.
  Future<WeekProposal> week({
    required PlanIntake intake,
    required PlanWeek slot,
    List<String> violations,
  });

  /// A mid-session substitution.
  Future<SwapProposal> swap({
    required String message,
    required Session session,
  });
}

/// One thing said during intake.
@immutable
class PlannerTurn {
  const PlannerTurn({required this.text, required this.fromCoach});

  final String text;
  final bool fromCoach;
}

/// Why a plan could not be built.
enum PlanFailure {
  signedOut,
  notEntitled,
  limitReached,

  /// The coach could not produce a week this lifter could actually do, twice.
  couldNotAgree,

  unavailable;

  String get message => switch (this) {
    signedOut => 'Sign in to build a plan.',
    notEntitled => 'Planning is part of the paid plan.',
    limitReached => 'That is all the planning for now. Try again later.',
    couldNotAgree =>
      'Your coach could not put a week together that fits. Try again, or '
          'tell it more about what you can do.',
    unavailable => 'Could not reach your coach. Tracking works without one.',
  };
}

@immutable
class PlanException implements Exception {
  const PlanException(this.failure);

  final PlanFailure failure;

  @override
  String toString() => failure.message;
}

/// Builds a block: the arc first, then each week, checking as it goes.
///
/// **A rejected week is retried with its own violations as the brief.** That is
/// the whole reason `PlanValidator` writes them as instructions — "Move the
/// Wednesday session: they only train on Monday, Thursday" goes straight back
/// to the model, which is a far better correction than asking again and hoping.
///
/// One retry, not more. A model that cannot honour the rules on the second
/// attempt is not going to on the fifth, and every attempt is a paid call made
/// while somebody watches a spinner.
class PlanGenerator {
  const PlanGenerator({
    required this.planner,
    this.validator = const PlanValidator(),
    this.attemptsPerWeek = 2,
  });

  final CoachPlanner planner;
  final PlanValidator validator;

  /// How many times a single week may be asked for before giving up on it.
  final int attemptsPerWeek;

  /// How many weeks are filled in up front.
  ///
  /// **Not the whole block.** Weeks are generated a week ahead because a plan
  /// built eight weeks deep on day one is eight weeks of guesses about a lifter
  /// nobody has watched train yet — and every one of them is a paid call the
  /// lifter might never reach. Two is enough to look like a plan and to cover
  /// somebody who trains ahead of schedule.
  static const int weeksGeneratedUpFront = 2;

  /// Generates a draft block. Throws [PlanException].
  Future<Plan> generate({
    required PlanIntake intake,
    required List<Session> log,
    required DateTime startDate,
    String? id,
  }) async {
    final arc = await planner.skeleton(intake: intake);
    if (arc.isEmpty) throw const PlanException(PlanFailure.couldNotAgree);

    final planId = id ?? 'plan-${startDate.toIso8601String()}';
    final sessions = <PlanSession>[];

    for (final slot in arc.take(weeksGeneratedUpFront)) {
      sessions.addAll(
        await _week(
          intake: intake,
          slot: slot,
          log: log,
          planId: planId,
          startDate: startDate,
        ),
      );
    }

    return Plan(
      id: planId,
      startDate: startDate,
      weeks: arc.length,
      status: PlanStatus.draft,
      goal: intake.goal,
      profile: intake.profileFor(),
      arc: arc,
      sessions: sessions,
    );
  }

  /// Fills in one week, retrying once with what was wrong the first time.
  ///
  /// Public because weeks are generated a week ahead: the app calls this again
  /// as the block runs, not only while building it.
  Future<List<PlanSession>> fillWeek({
    required Plan plan,
    required PlanWeek slot,
    required PlanIntake intake,
    required List<Session> log,
  }) => _week(
    intake: intake,
    slot: slot,
    log: log,
    planId: plan.id,
    startDate: plan.startDate,
  );

  Future<List<PlanSession>> _week({
    required PlanIntake intake,
    required PlanWeek slot,
    required List<Session> log,
    required String planId,
    required DateTime startDate,
  }) async {
    var violations = const <String>[];

    for (var attempt = 0; attempt < attemptsPerWeek; attempt++) {
      final proposal = await planner.week(
        intake: intake,
        slot: slot,
        violations: violations,
      );
      final verdict = validator.check(
        proposal,
        profile: intake.profileFor(isDeload: slot.isDeload),
        log: log,
      );

      if (verdict.isAccepted) {
        return <PlanSession>[
          for (final session in verdict.sessions)
            PlanSession(
              id: '$planId-w${slot.number}-d${session.weekday}',
              weekNumber: slot.number,
              weekday: session.weekday,
              scheduledDate: _dateFor(startDate, slot.number, session.weekday),
              kind: session.kind,
              movements: session.movements,
              rationale: session.rationale,
            ),
        ];
      }
      violations = verdict.violations;
    }

    throw const PlanException(PlanFailure.couldNotAgree);
  }

  /// The calendar date of a weekday in a given week of the block.
  ///
  /// Weeks run from the block's start date, not from Monday. A block that began
  /// on a Wednesday has its week 1 running Wednesday to Tuesday, which is what
  /// somebody who started midweek actually experiences — anchoring to Monday
  /// would give them a three-day first week nobody asked for.
  static DateTime _dateFor(DateTime startDate, int weekNumber, int weekday) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final offsetIntoWeek = (weekday - start.weekday + 7) % 7;
    return start.add(Duration(days: (weekNumber - 1) * 7 + offsetIntoWeek));
  }
}
