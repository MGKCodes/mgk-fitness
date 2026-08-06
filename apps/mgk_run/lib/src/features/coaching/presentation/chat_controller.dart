import 'package:flutter/foundation.dart';

import '../data/adaptation_service.dart';
import '../data/coach_client.dart';
import '../data/coach_errors.dart';
import '../data/coach_memory_repository.dart';
import '../domain/coach_memory.dart';
import '../domain/training_plan.dart';
import 'chat_entry.dart';

/// Drives the open coach conversation — the one a runner can ask anything, as
/// opposed to the slot-filling intake in `onboarding_controller.dart`.
///
/// Three things are deliberate here.
///
/// **The brief is written per turn, not once.** It is a snapshot of what the app
/// knows — the plan, the last runs, the projections — and a run recorded between
/// two questions must change the answer to the second. Asking for it lazily also
/// keeps the controller free of the repository: it takes a function, so a test
/// hands it a string and the shell hands it `CoachBrief.write`.
///
/// **An intent is handed over, never acted on.** When the coach comes back
/// wanting to change the week, this calls [onAdaptRequest] with the request in
/// the runner's own words. What comes back is a *validated* revision, which is
/// attached to the coach's reply as a [ChatProposal] and waits there. Nothing
/// is written until [applyProposal] — the model proposes, the validator
/// disposes, the runner approves (CLAUDE.md rule 2).
///
/// **The approval lives in the conversation.** It used to be a modal sheet
/// thrown over the screen, which meant a runner who asked for a change in a
/// sentence had to leave the conversation to agree to it, and the transcript
/// kept no record of what they had agreed. The decision now stays where the
/// reasoning was, and is still there next week when they wonder why Sunday
/// moved.
///
/// **A failure keeps the runner's message.** The turn that failed stays in the
/// transcript with the real reason beside it, so a rate-limited runner can see
/// what they asked and send it again when the window clears, rather than
/// retyping it against a generic error.
///
/// **Memory is tiered, and this is where both tiers are written.** Every turn
/// is appended to the verbatim transcript as it happens, so a force-quit
/// mid-sentence keeps what was said. The small rolling summary is rewritten
/// only when a conversation *ends* — it costs a model call against an
/// allowance of six an hour, and summarising per turn would both spend that
/// in ten minutes and produce a copy of a copy.
class ChatController extends ChangeNotifier {
  ChatController({
    required CoachChatClient client,
    required Future<String> Function() brief,
    this.onAdaptRequest,
    this.onLogRunRequest,
    this.onEditRunRequest,
    this.onSetGoalRequest,
    this.onApplyRun,
    this.onApplyRevision,
    this.onApplyGoal,
    DateTime Function()? now,
    CoachMemoryRepository? memory,
    CoachSummariseClient? summariser,
    String Function()? newConversationId,
  }) : _client = client,
       _brief = brief,
       _memory = memory,
       _summariser = summariser,
       _now = now ?? DateTime.now,
       _newConversationId =
           newConversationId ??
           (() => 'coach-${DateTime.now().microsecondsSinceEpoch}');

  final CoachChatClient _client;
  final Future<String> Function() _brief;

  /// Where the transcript and the rolling summary live. Null keeps the
  /// conversation to this session, which is what a build with no database does.
  final CoachMemoryRepository? _memory;

  /// Rewrites the rolling summary. Separate from [_client] because a build can
  /// have a coach that talks without one that remembers.
  final CoachSummariseClient? _summariser;

  final String Function() _newConversationId;
  final DateTime Function() _now;

  /// The conversation being written to, created on the first message rather
  /// than at construction — opening the app and saying nothing should not leave
  /// an empty conversation behind.
  String? _conversationId;

  /// Turns appended since the summary was last rewritten. Guards the model call
  /// at the end: nothing new means nothing to summarise, and paying to be told
  /// the memory is unchanged is the one thing the surface refuses anyway.
  int _unsummarised = 0;

  /// True while a summary is being written, so two closes cannot race into two
  /// model calls.
  bool _summarising = false;

  /// Turns a request in the runner's words into a validated revision, or null
  /// when none could be produced. **Proposes only** — it must not write.
  ///
  /// Null when there is nothing to adapt: a build with no plan client, or a
  /// runner with no plan.
  final Future<ChatProposal?> Function(String request)? onAdaptRequest;

  /// Turns "I did 5k in 26 minutes this morning" into a validated run to
  /// confirm. Null means the build cannot log runs from conversation, and the
  /// intent is then ignored rather than half-honoured.
  final Future<RunProposal?> Function(String request)? onLogRunRequest;

  /// Resolves "yesterday's run was actually 6k" to a validated run to confirm.
  /// Null when the day matched no run, or more than one.
  final Future<RunProposal?> Function(String request)? onEditRunRequest;

  /// Turns "I've entered Manchester on 5 April" into a validated target to
  /// confirm. Null when the build cannot change a goal from conversation, and
  /// the intent is then ignored rather than half-honoured — which is the safe
  /// half to be missing, since honouring it supersedes a plan.
  final Future<GoalProposal?> Function(String request)? onSetGoalRequest;

  /// Writes a confirmed run — added, or corrected in place. Takes the whole
  /// proposal rather than the draft, because whether there is a run to correct
  /// is what decides between the two, and only the proposal knows.
  final Future<bool> Function(RunProposal proposal)? onApplyRun;

  /// Writes an approved revision. Returns whether it was stored, so a failed
  /// write leaves the offer standing rather than pretending it took.
  final Future<bool> Function(TrainingWeek week)? onApplyRevision;

  /// Rebuilds the plan around an approved target. Returns whether it took —
  /// and the failure case matters more here than anywhere else, because a card
  /// that said "done" over a plan that did not change would leave the runner
  /// training for the wrong race with nothing on screen disagreeing.
  final Future<bool> Function(GoalProposal proposal)? onApplyGoal;

  /// What the dock draws: the messages, plus anything the app has attached to
  /// them. [messages] stays the wire view of the same list.
  final List<ChatEntry> _entries = <ChatEntry>[];
  bool _busy = false;
  bool _proposing = false;
  String? _error;

  /// The transcript so far, oldest first — the wire view.
  List<ChatMessage> get messages =>
      List<ChatMessage>.unmodifiable(_entries.map((e) => e.message));

  /// The transcript as the dock shows it, proposals attached.
  List<ChatEntry> get entries => List<ChatEntry>.unmodifiable(_entries);

  /// A turn is in flight.
  bool get isBusy => _busy;

  /// A change is being worked out. Distinct from [isBusy] because it happens
  /// *after* the reply is on screen, and the runner should see that something
  /// is still coming rather than a finished-looking answer.
  bool get isProposing => _proposing;

  /// A user-presentable reason the last turn failed, if any. Already phrased for
  /// the runner — [CoachLimitException] carries its own wording so an allowance
  /// that has run out does not read as "something went wrong".
  String? get error => _error;

  /// Whether the composer should accept another message.
  bool get canSend => !_busy;

  /// True before the first word is said either way.
  bool get isEmpty => _entries.isEmpty;

  /// Bumped when something outside the dock wants the conversation opened — a
  /// session brief handing over, say. A counter rather than a bool because the
  /// same request can be made twice and must reopen a dock the runner closed in
  /// between.
  final ValueNotifier<int> openRequests = ValueNotifier<int>(0);

  /// Opens the conversation and asks [text] — the hand-off from a surface that
  /// has said everything it can deterministically and needs judgement next.
  Future<void> ask(String text) async {
    openRequests.value++;
    await send(text);
  }

  /// Opens the conversation **on something the coach has already said**.
  ///
  /// The dock shows the coach's latest observation — "Longest one yet." — and
  /// tapping it used to open a blank transcript, so the coach said something
  /// interesting and forgot it the moment the runner engaged. Seeding the line
  /// as the first turn means the conversation starts mid-thought, with
  /// something to reply to.
  ///
  /// Only into an empty transcript: a conversation already under way is not
  /// interrupted with an observation, and a restored one already has its own
  /// history. Persisted like any other turn, so a reply on the next launch is
  /// not stranded above the thing it replies to.
  Future<void> openWithNote(String line) async {
    openRequests.value++;
    final trimmed = line.trim();
    if (trimmed.isEmpty || _entries.isNotEmpty) return;
    _entries.add(ChatEntry(message: ChatMessage.coach(trimmed), at: _now()));
    notifyListeners();
    await _remember(CoachRole.assistant, trimmed);
  }

  @override
  void dispose() {
    openRequests.dispose();
    super.dispose();
  }

  /// Loads the last conversation back into the dock.
  ///
  /// Without this the coach forgot the runner every launch: the summary told it
  /// *about* them, but the runner opened a blank transcript and could not see
  /// what they had already been told. Best-effort — a memory that will not load
  /// is an empty dock, never a broken one.
  Future<void> restore() async {
    final memory = _memory;
    if (memory == null || _entries.isNotEmpty) return;
    try {
      final id = await memory.lastConversationId();
      if (id == null) return;
      final turns = await memory.transcript(id);
      if (turns.isEmpty) return;
      _conversationId = id;
      // Proposals are deliberately not restored. A revision offered last week
      // was validated against a week that has since been lived; re-offering it
      // would hand the runner a stale change to approve. The words stay, the
      // button does not.
      _entries.addAll(
        turns.map(
          (t) => ChatEntry(
            message: t.role == CoachRole.user
                ? ChatMessage.user(t.text)
                : ChatMessage.coach(t.text),
            at: t.at,
          ),
        ),
      );
      notifyListeners();
    } catch (_) {
      // A dock that opens empty beats one that fails to open.
    }
  }

  /// Ends the conversation: rewrites the rolling summary from what was said,
  /// then starts a fresh transcript for whatever is asked next.
  ///
  /// Called when the dock closes and on dispose. **Idempotent and silent** —
  /// housekeeping the runner did not ask for, so a failure leaves the existing
  /// summary standing and says nothing.
  Future<void> endConversation() async {
    final memory = _memory;
    final summariser = _summariser;
    final id = _conversationId;
    if (memory == null || summariser == null || id == null) return;
    if (_unsummarised == 0 || _summarising) return;

    _summarising = true;
    final covered = _unsummarised;
    try {
      final previous = await memory.summary();
      final transcript = await memory.transcript(id);
      if (transcript.isEmpty) return;

      final rewritten = await summariser.summarise(
        previous: previous?.text,
        transcript: <ChatMessage>[
          for (final t in transcript)
            t.role == CoachRole.user
                ? ChatMessage.user(t.text)
                : ChatMessage.coach(t.text),
        ],
      );
      // Null means "could not rewrite" — keep what we have. An empty string is
      // a legitimate answer meaning "nothing worth keeping", and is equally not
      // a reason to throw away a summary that already exists.
      if (rewritten == null || rewritten.trim().isEmpty) return;

      await memory.replaceSummary(rewritten.trim(), turnsCovered: covered);
      _unsummarised = 0;
      // What is said next starts a new conversation, so the summariser is never
      // handed turns it has already folded in.
      _conversationId = null;
    } catch (_) {
      // Silent on purpose: nothing the runner did failed.
    } finally {
      _summarising = false;
    }
  }

  /// Sends [text] and appends the coach's reply.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;

    // The contract keeps "what they just said" out of the history, so the
    // transcript is captured before the new message joins it.
    final history = messages;

    _entries.add(ChatEntry(message: ChatMessage.user(trimmed), at: _now()));
    _busy = true;
    _error = null;
    notifyListeners();

    // Written before the call goes out, not after it comes back: a question
    // asked into a tunnel is still a question the runner asked.
    await _remember(CoachRole.user, trimmed);

    CoachIntent? intent;
    try {
      final turn = await _client.chat(
        brief: await _writeBrief(),
        history: history,
        message: trimmed,
      );
      _entries.add(
        ChatEntry(message: ChatMessage.coach(turn.reply), at: _now()),
      );
      await _remember(CoachRole.assistant, turn.reply);
      intent = turn.intent;
    } on CoachException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'The coach hit a problem. Please try again.';
    } finally {
      _busy = false;
      notifyListeners();
    }

    // After the reply is on screen, not before: the runner should read what the
    // coach said and *then* see the change it is proposing.
    if (intent == null) return;
    if (intent.isAdaptWeek) {
      await _proposeFor(intent.request);
    } else if (intent.isLogRun) {
      await _proposeRunFor(intent.request);
    } else if (intent.isEditRun) {
      await _proposeEditFor(intent.request);
    } else if (intent.isSetGoal) {
      await _proposeGoalFor(intent.request);
    }
  }

  /// Asks for a validated target and pins it to the reply that raised it.
  ///
  /// Its own method rather than a branch of [_proposeRunFor] because the
  /// refusals differ, and here they are worth saying out loud. A run that
  /// cannot be read is a small loss; a goal that cannot be read is a runner who
  /// has just told their coach they entered a race and been met with silence.
  Future<void> _proposeGoalFor(String request) async {
    final setGoal = onSetGoalRequest;
    if (setGoal == null || _entries.isEmpty) return;

    _proposing = true;
    notifyListeners();
    GoalProposal? proposal;
    try {
      proposal = await setGoal(request);
    } catch (_) {
      proposal = null;
    } finally {
      _proposing = false;
    }

    if (proposal == null) {
      _entries.add(
        ChatEntry(
          message: const ChatMessage.coach(
            "I couldn't pin that down to a distance and a date. Tell me what "
            "you are running and when, and I'll set it up.",
          ),
          at: _now(),
        ),
      );
      notifyListeners();
      return;
    }

    final last = _entries.lastIndexWhere((e) => !e.isUser);
    if (last < 0) return;
    _entries[last] = _entries[last].withProposal(proposal);
    notifyListeners();
  }

  /// Asks for a validated correction and pins it to the reply that mentioned it.
  ///
  /// Separate from [_proposeRunFor] because the failure it has to explain is a
  /// different one: not "I could not read that as a run" but "I could not tell
  /// which run you meant", which is a question the runner can answer.
  Future<void> _proposeEditFor(String request) async {
    final edit = onEditRunRequest;
    if (edit == null || _entries.isEmpty) return;

    _proposing = true;
    notifyListeners();
    RunProposal? proposal;
    try {
      proposal = await edit(request);
    } catch (_) {
      proposal = null;
    } finally {
      _proposing = false;
    }

    if (proposal == null) {
      _entries.add(
        ChatEntry(
          message: const ChatMessage.coach(
            "I couldn't tell which run you meant. Which day was it?",
          ),
          at: _now(),
        ),
      );
      notifyListeners();
      return;
    }

    final last = _entries.lastIndexWhere((e) => !e.isUser);
    if (last < 0) return;
    _entries[last] = _entries[last].withProposal(proposal);
    notifyListeners();
  }

  /// Asks for a validated run and pins it to the reply that mentioned it.
  ///
  /// Deliberately the same shape as [_proposeFor]: a proposal that cannot be
  /// made is said plainly rather than dropped, because the coach has just
  /// acknowledged a run and a runner who sees nothing appear will reasonably
  /// assume it was logged.
  Future<void> _proposeRunFor(String request) async {
    final log = onLogRunRequest;
    if (log == null || _entries.isEmpty) return;

    _proposing = true;
    notifyListeners();
    RunProposal? proposal;
    try {
      proposal = await log(request);
    } catch (_) {
      proposal = null;
    } finally {
      _proposing = false;
    }

    if (proposal == null) {
      _entries.add(
        ChatEntry(
          message: const ChatMessage.coach(
            "I couldn't make that into a run. Tell me how far and how long and "
            "I'll add it.",
          ),
          at: _now(),
        ),
      );
      notifyListeners();
      return;
    }

    final last = _entries.lastIndexWhere((e) => !e.isUser);
    if (last < 0) return;
    _entries[last] = _entries[last].withProposal(proposal);
    notifyListeners();
  }

  /// Asks for a validated revision and pins it to the reply that explained it.
  Future<void> _proposeFor(String request) async {
    final adapt = onAdaptRequest;
    if (adapt == null || _entries.isEmpty) return;

    _proposing = true;
    notifyListeners();
    ChatProposal? proposal;
    // The validator's reason, when it had one worth repeating.
    String? refusal;
    try {
      proposal = await adapt(request);
    } on AdaptationRefused catch (e) {
      // The model produced a week and the validator would not stand behind it.
      // Falling back to the generic line here would tell a runner to rephrase
      // a request whose problem is not its wording — asked to move a session
      // to a day they said they were busy, no rewording will help.
      refusal = e.message;
    } catch (_) {
      proposal = null;
    } finally {
      _proposing = false;
    }

    // Nothing valid came back. Said plainly rather than silently: the coach
    // offered a change and the runner is entitled to know it did not survive.
    if (proposal == null) {
      _entries.add(
        ChatEntry(
          message: ChatMessage.coach(
            refusal ??
                "I couldn't work that change out. Try telling me what you "
                    'want differently.',
          ),
          at: _now(),
        ),
      );
      notifyListeners();
      return;
    }

    final last = _entries.lastIndexWhere((e) => !e.isUser);
    if (last < 0) return;
    _entries[last] = _entries[last].withProposal(proposal);
    notifyListeners();
  }

  /// The runner said yes. Writes the week, then marks the offer in place so the
  /// transcript records the decision rather than losing it.
  Future<void> applyProposal(ChatEntry entry) async {
    final proposal = entry.proposal;
    if (proposal == null || !proposal.isPending) return;

    final index = _entries.indexOf(entry);
    if (index < 0) return;

    var stored = false;
    try {
      // Exhaustive by construction: a new kind of proposal will not compile
      // until it is given a way to be applied, which is the point of sealing
      // the type. A proposal that offered a change and then did nothing when
      // the runner tapped Apply is the failure worth making impossible.
      stored = switch (proposal) {
        ChatProposal(:final week) =>
          await (onApplyRevision?.call(week) ?? Future<bool>.value(false)),
        RunProposal() =>
          await (onApplyRun?.call(proposal) ?? Future<bool>.value(false)),
        GoalProposal() =>
          await (onApplyGoal?.call(proposal) ?? Future<bool>.value(false)),
      };
    } catch (_) {
      stored = false;
    }
    _entries[index] = _entries[index].withProposal(
      proposal.withState(stored ? ProposalState.applied : ProposalState.failed),
    );
    notifyListeners();
  }

  /// The runner said no. The offer stays in the transcript, marked — "I asked
  /// and decided against it" is part of the record.
  void declineProposal(ChatEntry entry) {
    final proposal = entry.proposal;
    if (proposal == null || !proposal.isPending) return;
    final index = _entries.indexOf(entry);
    if (index < 0) return;
    _entries[index] = _entries[index].withProposal(
      proposal.withState(ProposalState.declined),
    );
    notifyListeners();
  }

  /// Appends one turn to the stored transcript.
  ///
  /// Awaited rather than fired and forgotten: the repository contracts that the
  /// future completes once the turn is **on disk**, and that guarantee is worth
  /// the millisecond. Failures are swallowed — losing a line of history must
  /// never cost the runner their conversation.
  Future<void> _remember(CoachRole role, String text) async {
    final memory = _memory;
    if (memory == null) return;
    try {
      final id = _conversationId ??= _newConversationId();
      await memory.appendTurn(conversationId: id, role: role, text: text);
      _unsummarised++;
    } catch (_) {
      // See above.
    }
  }

  /// The brief, or an empty one if it could not be written.
  ///
  /// A brief is context, not a precondition. Failing the whole turn because the
  /// plan store hiccuped would take the coach away at the moment a runner is
  /// most likely to be asking about it; the model simply answers with less.
  Future<String> _writeBrief() async {
    try {
      return await _brief();
    } catch (_) {
      return '';
    }
  }
}
