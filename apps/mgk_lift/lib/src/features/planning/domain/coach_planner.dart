import 'package:meta/meta.dart';

import '../../tracking/domain/session.dart';
import 'intake_flow.dart';
import 'plan_intake.dart';
import 'plan_builder.dart';
import 'plan_proposal.dart';

/// The coach, as the planner needs it. Implemented against the Edge Function;
/// faked in tests and the preview harness.
abstract interface class CoachPlanner {
  /// One turn of the intake conversation.
  ///
  /// [progress] carries what is known AND what was declined, so the coach is
  /// told the same order and the same "do not ask again" the screen works
  /// from rather than reconstructing either from the transcript.
  Future<IntakeTurn> intake({
    required IntakeProgress progress,
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

  /// The plan exists and the database refused it. **Not a connection
  /// problem**, and saying it was one is how a missing column passed for a bad
  /// signal for seven weeks: every save failed, and every lifter was told to
  /// check their network.
  notSaved,

  /// The server answered, with an error of its own. Also not the lifter's
  /// connection.
  serverError,

  /// No answer at all: no network, or a request that ran out of time.
  unavailable;

  String get message => switch (this) {
    signedOut => 'Sign in to build a plan.',
    notEntitled => 'Planning is part of the paid plan.',
    limitReached => 'That is all the planning for now. Try again later.',
    couldNotAgree =>
      'Your coach could not put a week together that fits. Try again, or '
          'tell it more about what you can do.',
    notSaved =>
      'Your plan was built but could not be saved. Your answers are kept, '
          'so trying again is one tap.',
    serverError =>
      'Something went wrong on our side, not yours. Try again in a minute.',
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
