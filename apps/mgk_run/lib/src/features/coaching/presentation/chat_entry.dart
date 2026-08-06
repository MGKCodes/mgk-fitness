import '../data/coach_client.dart';
import '../domain/goal_draft.dart';
import '../domain/plan_shape.dart';
import '../domain/training_plan.dart';
import '../../history/domain/run_draft.dart';
import '../domain/week_adaptation.dart';

/// Where a proposal has got to.
enum ProposalState {
  /// Offered, waiting on the runner.
  pending,

  /// The runner said yes and the week was written.
  applied,

  /// The runner said no. Kept in the transcript rather than removed — "I asked
  /// and decided against it" is part of the record.
  declined,

  /// Something went wrong writing it. The offer stands.
  failed,
}

/// Something validated that the coach is offering, attached to the message that
/// explains it, waiting on the runner to say yes.
///
/// Sealed because the set is closed by design: every kind of proposal is a thing
/// Dart has already checked, and adding one means adding a validator alongside
/// it. A `switch` over these is exhaustive, so a new kind cannot be added
/// without every place that renders or applies one being made to handle it —
/// which is exactly the reminder wanted, since the alternative is a proposal
/// that silently does nothing when the runner taps Apply.
sealed class CoachProposal {
  const CoachProposal({this.state = ProposalState.pending});

  final ProposalState state;

  bool get isPending => state == ProposalState.pending;

  CoachProposal withState(ProposalState next);
}

/// A **validated** week revision the coach is offering, attached to the message
/// that explains it.
///
/// The model never produced this: it produced a sentence and an intent, which
/// the adaptation service turned into a revision and the validator accepted or
/// refused (CLAUDE.md rule 2). By the time one of these exists, the week inside
/// it is already known to be sound — the runner is approving a change, not
/// approving a model's output.
class ChatProposal extends CoachProposal {
  const ChatProposal({required this.week, required this.changes, super.state});

  /// The week as it would be. Written only if the runner says yes.
  final TrainingWeek week;

  /// What differs, for the runner to read before deciding.
  final List<SessionChange> changes;

  @override
  ChatProposal withState(ProposalState next) =>
      ChatProposal(week: week, changes: changes, state: next);
}

/// A **validated** run the coach heard the runner mention, offered for them to
/// confirm before it becomes a row in their log.
///
/// The model never produced this either. It read a sentence into fields on the
/// `log_run` surface, and [RunDraft] decided whether those fields describe a
/// possible run (ADR-0016). By the time one of these exists the numbers are
/// already known to be sane — the runner is confirming that this is the run
/// they did, not proof-reading a model's arithmetic.
///
/// Confirmed rather than written straight in, because "I did 5k in 26 minutes"
/// is a sentence a model can mishear, and a run nobody checked is indis-
/// tinguishable from one they reported once it is in the log.
class RunProposal extends CoachProposal {
  const RunProposal({required this.draft, this.runId, super.state});

  /// The run as it would be stored. Written only if the runner says yes.
  final RunDraft draft;

  /// The run being corrected, or null to add a new one.
  ///
  /// One field rather than two proposal types, because the runner is doing the
  /// same thing either way — reading a run and saying yes. What differs is only
  /// where it lands, and that is the applier's concern.
  final String? runId;

  bool get isEdit => runId != null;

  @override
  RunProposal withState(ProposalState next) =>
      RunProposal(draft: draft, runId: runId, state: next);
}

/// A **validated** change to what the runner is training for, offered before
/// their plan is rebuilt around it.
///
/// The one proposal here that does not add or amend a row — it replaces a
/// block. Accepting it supersedes the plan the runner has been working through
/// and every week in it, which is why [supersedes] exists: a card that said
/// only "half marathon, 4 October" would be asking them to approve the new
/// thing without showing them the cost of it.
///
/// Validated by [GoalDraft] before it gets this far, so the runner is deciding
/// whether this is what they meant, not whether the date is possible.
class GoalProposal extends CoachProposal {
  const GoalProposal({
    required this.draft,
    required this.shape,
    this.supersedes,
    super.state,
  });

  /// The target as it would be. Written only if the runner says yes.
  final GoalDraft draft;

  /// What kind of plan this becomes (ADR-0011) — a block counting down, a
  /// horizon with nothing to taper into, or no plan at all.
  final PlanShape shape;

  /// How many weeks of the current plan are being thrown away, or null when
  /// there is no plan to lose. Shown on the card, because "this replaces your
  /// 16 week block" is the part of the decision the runner cannot reconstruct.
  final int? supersedes;

  @override
  GoalProposal withState(ProposalState next) => GoalProposal(
    draft: draft,
    shape: shape,
    supersedes: supersedes,
    state: next,
  );
}

/// One line of the conversation as the dock shows it.
///
/// Separate from [ChatMessage], which is the wire type. A proposal is a thing
/// the *app* attaches to a reply after the fact, and putting it on the message
/// would put display state into the contract with the server.
class ChatEntry {
  const ChatEntry({required this.message, this.proposal, this.at});

  final ChatMessage message;

  /// When it was said. Null only for a message with no stored turn behind it.
  /// Drives the day dividers, which only started meaning anything once
  /// conversations survived a relaunch.
  final DateTime? at;

  /// A change offered alongside this message, if any. Only ever on a coach
  /// message: the runner asks in words, the coach answers with a proposal.
  final CoachProposal? proposal;

  bool get isUser => message.isUser;
  String get text => message.text;

  ChatEntry withProposal(CoachProposal? next) =>
      ChatEntry(message: message, proposal: next, at: at);
}
