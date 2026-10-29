import '../../planning/domain/coach_planner.dart';
import '../../planning/domain/intake_flow.dart';
import '../../planning/domain/plan_builder.dart';
import '../../planning/domain/plan_intake.dart';
import '../../planning/domain/plan_proposal.dart';
import '../../tracking/domain/session.dart';
import 'coach.dart';

/// Asks whether the coach may send, before it does: true to carry on.
///
/// The shell's answer is the consent sheet when there is no yes on the account
/// yet, and true at once when there is.
typedef AskFirst = Future<bool> Function();

/// The coach, asking first wherever a message comes from (issue #10).
///
/// **Why a wrapper rather than a check at each screen.** The shell asks at the
/// doors it owns: the coach mark and *Build a plan*. But requests also start
/// from places it does not draw, such as a swap in the middle of a session, a
/// conversation left open while the answer was withdrawn on another phone, or
/// a send after the server refused. Each of those would need the same question
/// added by hand, and the first one forgotten would send a lifter's training
/// to OpenRouter without a yes, or show them an error with no way to give one.
/// Wrapping the coach the shell hands out puts the question in front of every
/// request, and nothing downstream has to know it is there.
///
/// A no is [CoachFailure.consentRequired], so the screen says nothing was sent.
/// The clients underneath refuse again on their own (`SupabaseCoach`), so a
/// coach handed out without this wrapper still cannot send.
class ConsentGatedCoach implements CoachService {
  const ConsentGatedCoach(this._inner, {required AskFirst askFirst})
    : _askFirst = askFirst;

  final CoachService _inner;
  final AskFirst _askFirst;

  @override
  Future<String> ask(String message, {required String conversationId}) async {
    if (!await _askFirst()) {
      throw const CoachException(CoachFailure.consentRequired);
    }
    return _inner.ask(message, conversationId: conversationId);
  }
}

/// The planner, asking first: the intake, a week, and a mid-session swap.
/// See [ConsentGatedCoach] for why.
class ConsentGatedPlanner implements CoachPlanner {
  const ConsentGatedPlanner(this._inner, {required AskFirst askFirst})
    : _askFirst = askFirst;

  final CoachPlanner _inner;
  final AskFirst _askFirst;

  Future<void> _asked() async {
    if (!await _askFirst()) {
      throw const PlanException(PlanFailure.consentRequired);
    }
  }

  @override
  Future<IntakeTurn> intake({
    required IntakeProgress progress,
    required List<PlannerTurn> history,
  }) async {
    await _asked();
    return _inner.intake(progress: progress, history: history);
  }

  @override
  Future<PlanProposal> plan({
    required PlanIntake intake,
    required List<int> weekdays,
    required List<String> catalogue,
    List<String> violations = const <String>[],
  }) async {
    await _asked();
    return _inner.plan(
      intake: intake,
      weekdays: weekdays,
      catalogue: catalogue,
      violations: violations,
    );
  }

  @override
  Future<SwapProposal> swap({
    required String message,
    required Session session,
  }) async {
    await _asked();
    return _inner.swap(message: message, session: session);
  }
}
