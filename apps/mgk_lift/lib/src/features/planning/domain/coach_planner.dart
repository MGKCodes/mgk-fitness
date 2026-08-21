import 'package:meta/meta.dart';

import '../../tracking/domain/session.dart';
import 'plan_intake.dart';
import 'plan_builder.dart';
import 'plan_proposal.dart';

/// The coach, as the planner needs it. Implemented against the Edge Function;
/// faked in tests and the preview harness.
abstract interface class CoachPlanner {
  /// One turn of the intake conversation.
  Future<IntakeTurn> intake({
    required PlanIntake known,
    required List<PlannerTurn> history,
  });

  /// A whole training week, unchecked.
  ///
  /// The coach is free to invent the shape; [PlanShape] decides whether what
  /// came back is usable, and [PlanBuilder] runs the loop between them.
  /// [catalogue] is the movement names it may use, filtered to the equipment
  /// this lifter has.
  Future<PlanProposal> plan({
    required PlanIntake intake,
    required List<int> weekdays,
    required List<String> catalogue,
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

// Plans are built by [PlanBuilder] now.
//
// `PlanGenerator` orchestrated skeleton -> week -> validate -> repeat, which
// was the right shape while a plan was a list of sessions written in advance.
// A standing plan is a rule, so there is nothing to generate week by week: the
// coach proposes one week, PlanShape checks it, and PlanTemplate is the floor.
// See docs/plan-model.md.
