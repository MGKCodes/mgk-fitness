import '../../history/domain/run_draft.dart';
import 'coach_mappers.dart';
import '../domain/intake_conversation.dart';
import '../domain/intake_slots.dart';

/// The coach seam. The real implementation ([CoachService]) calls the Edge
/// Function; a fake drives the onboarding UI in the web preview and in tests
/// with no key and no network. Keeping this abstract is what lets the whole
/// onboarding flow be built and verified before the function is deployed.
abstract interface class CoachClient {
  /// One onboarding turn: given the running slot state and conversation so far,
  /// return the coach's reply and the slots extracted this turn.
  Future<IntakeTurn> intake({
    required IntakeSlots slots,
    required List<IntakeMessage> history,
  });
}

/// The **conversation** seam — the coach a runner can ask anything, as opposed
/// to the slot-filling intake that builds a plan.
///
/// Deliberately a second interface rather than another method on [CoachClient].
/// The two surfaces answer different questions and have different lifetimes: a
/// build can ship intake without chat, and every existing double implements
/// [CoachClient] without knowing about this. [CoachService] implements both.
abstract interface class CoachChatClient {
  /// One conversational turn.
  ///
  /// [brief] is the prose from `CoachBrief` — everything the app knows about
  /// this runner, written for a reader rather than serialised. [history] is the
  /// transcript **before** [message]; the message the runner just sent travels
  /// separately so the server never has to guess which turn it is answering.
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  });
}

/// The **memory** seam: condenses a conversation into what the coach should
/// still know about this runner next week.
///
/// A third interface for the same reason chat is a second one — it has its own
/// lifetime. Summarising happens when a conversation *ends*, not when a turn
/// is taken, so a build can ship the chat before it ships the memory, and a
/// test can drive one without standing up the other.
/// Reads a run out of what the runner said, for them to confirm.
///
/// Its own seam rather than a method on [CoachChatClient], for the reason the
/// others are separate: a build can ship chat without being able to log a run
/// from it, and every existing double would otherwise have to grow a method it
/// does not use. It also lets the preview harness offer the confirmation card
/// with no network behind it.
abstract interface class CoachLogRunClient {
  /// The run as a draft, or null when nothing usable could be read. The draft
  /// is **not** validated here — see `RunDraft.issues`, which runs where the
  /// result is shown so a refusal happens in front of the runner.
  Future<RunDraft?> logRun(String request);
}

/// Reads a correction out of what the runner said.
///
/// Split from [CoachLogRunClient] for the same reason that one is split from
/// chat: adding a run and correcting one are separately shippable, and the
/// second needs the runner's recent runs to resolve a day against while the
/// first does not.
abstract interface class CoachEditRunClient {
  /// Which run the runner is correcting, and what they changed. Null when
  /// nothing usable came back. Resolving the day to a row is the caller's job.
  Future<RunCorrection?> editRun(String request);
}

/// Reads a new target out of what the runner said.
///
/// Its own seam like the other two extractors, and for a sharper reason: this
/// is the only one whose result *replaces a plan* rather than adding a row. A
/// build that wires the conversation without wiring this gets a coach that can
/// talk about a new race and cannot act on one, which is the safe half to be
/// missing.
abstract interface class CoachSetGoalClient {
  /// What they said about their target, or null when nothing usable came back.
  /// Whether the distance is a distance and the date far enough away are
  /// `GoalDraft`'s questions, asked in front of the runner.
  Future<GoalChange?> setGoal(String request);
}

abstract interface class CoachSummariseClient {
  /// Rewrites the memory from [previous] plus the [transcript] since.
  ///
  /// Returns null when the memory could not be rewritten — a dead network, a
  /// spent allowance. Null means *keep what you have*, never *forget*: this is
  /// housekeeping the runner did not ask for and must never be shown as a
  /// failure, and the summary already on disk is still true.
  Future<String?> summarise({
    String? previous,
    required List<ChatMessage> transcript,
  });
}

/// One line of the conversation, as plain text.
///
/// Roles are `user` and `coach` — the chat surface's wire vocabulary, which is
/// not the intake surface's (`user` / `assistant`). They are kept apart rather
/// than unified because they are two contracts with the server, and collapsing
/// them into one type would make a change to either silently reshape the other.
class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  const ChatMessage.user(this.text) : role = 'user';
  const ChatMessage.coach(this.text) : role = 'coach';

  /// `'user'` or `'coach'`.
  final String role;
  final String text;

  bool get isUser => role == 'user';
}

/// What the coach wants done as a result of a turn.
///
/// The only kind is `adapt_week`, and it carries the change **in plain words**,
/// not as a plan edit. That is the point: the model says what the runner asked
/// for and the adaptation path decides what the plan becomes (CLAUDE.md rule 2).
class CoachIntent {
  const CoachIntent({required this.kind, required this.request});

  static const String adaptWeek = 'adapt_week';

  /// A run the runner mentioned in passing. Carries what they said, not
  /// numbers: the `log_run` surface reads it into fields and RunDraft decides
  /// whether those fields describe a possible run.
  static const String logRun = 'log_run';

  /// Every kind the app can route. Checked against, rather than compared to a
  /// single name — the server had this same filter hard-coded to `adapt_week`,
  /// which silently discarded `log_run` and looked exactly like a model that
  /// would not follow its prompt. Fixing it there and leaving this one is how
  /// the bug survived being fixed once.
  /// Correcting a run already in the log.
  static const String editRun = 'edit_run';

  /// Changing what the plan is aimed at: a race entered, a distance to reach,
  /// a date moved, or a goal given up. The most destructive of the four —
  /// accepting one supersedes the runner's block and every week in it.
  static const String setGoal = 'set_goal';

  static const List<String> kinds = <String>[
    adaptWeek,
    logRun,
    editRun,
    setGoal,
  ];

  final String kind;
  final String request;

  bool get isAdaptWeek => kind == adaptWeek;

  bool get isLogRun => kind == logRun;

  bool get isEditRun => kind == editRun;

  bool get isSetGoal => kind == setGoal;
}

/// One coach reply: what to show, and optionally what it wants to do next.
class ChatTurn {
  const ChatTurn({required this.reply, this.intent});

  final String reply;

  /// Null on an ordinary answer.
  final CoachIntent? intent;
}

/// The Edge Function's `chat` response → a [ChatTurn].
///
/// Tolerant on the way in, and **deliberately strict about the intent**: an
/// unrecognised kind, a missing request or a malformed object degrades to no
/// intent at all. An action the app doesn't understand must do nothing rather
/// than something approximate — the model can propose, but it cannot invent the
/// vocabulary it proposes in.
ChatTurn chatTurnFromResponse(Map<String, dynamic> res) => ChatTurn(
  reply: res['reply'] is String ? res['reply'] as String : '',
  intent: _intentFrom(res['intent']),
);

CoachIntent? _intentFrom(Object? raw) {
  if (raw is! Map) return null;
  final kind = raw['kind'];
  if (kind is! String || !CoachIntent.kinds.contains(kind)) return null;
  final request = raw['request'];
  if (request is! String || request.trim().isEmpty) return null;
  return CoachIntent(kind: kind, request: request.trim());
}
