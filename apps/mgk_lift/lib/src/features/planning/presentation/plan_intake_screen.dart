import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/coach_planner.dart';
import '../domain/intake_flow.dart';

/// The conversation that sets a block up.
///
/// **A conversation rather than a form**, which is the point and also the
/// harder thing to build: a form asks its questions in a fixed order and makes
/// somebody who answered three of them in one sentence answer them again. The
/// coach batches, skips ahead, and stops when it has enough.
///
/// What it gathers is merged, never replaced. Every intake turn returns every
/// field, and a null means "not learned this turn" — treating it as "forget it"
/// would erase an answer as soon as the next question was asked.
///
/// **The options under the newest turn do not make it a form.** [IntakeField]'s
/// own argument is that a fixed-order script is the failure to avoid, and none
/// of this is one: the composer stays live throughout, the chips answer
/// whichever field is still missing rather than whichever comes next in a
/// list, and the bar counts answers rather than position — so somebody who
/// says "4 days, home gym, bad shoulder" moves it three and is never asked
/// those again. The chips are there because tapping "3 days" standing in a gym
/// is easier than typing it, not because the conversation has been replaced.
class PlanIntakeScreen extends StatefulWidget {
  const PlanIntakeScreen({
    super.key,
    required this.planner,
    this.opener,
    this.initialTurns = const <PlannerTurn>[],
    this.initialKnown = const IntakeProgress(),
  });

  final CoachPlanner planner;

  /// The coach's first line, so the screen is not an empty box with a cursor.
  final String? opener;

  /// Turns to start from, after [opener].
  ///
  /// For previews and tests, which otherwise can only photograph the empty
  /// conversation — the state that is least like the one somebody is in when
  /// this screen matters. Nothing in the app passes it: a real intake has no
  /// history to restore, because an abandoned one is not resumed.
  final List<PlannerTurn> initialTurns;

  /// What those turns established, for the same reason.
  ///
  /// **Seeded rather than replayed.** What the lifter has answered comes back
  /// from the coach's extraction, not from parsing the transcript, so a
  /// preview that set only [initialTurns] would show three answers on screen
  /// and a progress bar reading zero — and would offer the first question's
  /// options underneath the fourth one.
  final IntakeProgress initialKnown;

  @override
  State<PlanIntakeScreen> createState() => _PlanIntakeScreenState();
}

class _PlanIntakeScreenState extends State<PlanIntakeScreen> {
  final List<PlannerTurn> _turns = <PlannerTurn>[];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  late IntakeProgress _known = widget.initialKnown;
  bool _waiting = false;
  PlanFailure? _failure;

  /// What the coach's latest turn said it was asking ([IntakeTurn.asking]).
  /// Null for the opener, which is the flow's own first question.
  IntakeField? _coachAsked;

  /// The field the options under the newest bubble are answering, and only
  /// while the coach has the floor.
  ///
  /// **The one the coach asked, when it is still open.** The coach chooses its
  /// question after reading the lifter's latest message, and the app chooses
  /// options after merging what the coach extracted from it — two readings of
  /// the same sentence, which could disagree. When they did, the coach asked
  /// about one thing above options for another. Now the options follow the
  /// question, and fall back to the first open field only when the coach did
  /// not say, or named something already settled.
  ///
  /// **Null after the lifter speaks**, so options never hang under somebody's
  /// own message waiting for a reply that has not arrived. Null when there is
  /// nothing left to ask, which is the same moment "Build my plan" appears.
  IntakeField? get _asking {
    if (_turns.isEmpty || !_turns.last.fromCoach) return null;
    final asked = _coachAsked;
    if (asked != null && !_known.has(asked)) return asked;
    return _known.next;
  }

  @override
  void initState() {
    super.initState();
    final opener = widget.opener;
    if (opener != null) {
      _turns.add(PlannerTurn(text: opener, fromCoach: true));
    }
    _turns.addAll(widget.initialTurns);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await _sendText(text);
  }

  /// Send [text] as the lifter's turn.
  ///
  /// [declining] is the field a tapped skip closes. It is recorded **before**
  /// the call rather than after it, because the point of declining is that the
  /// question stops being asked — and the reply to this very turn is chosen
  /// from what is still missing.
  Future<void> _sendText(String text, {IntakeField? declining}) async {
    if (_waiting) return;

    setState(() {
      _turns.add(PlannerTurn(text: text, fromCoach: false));
      if (declining != null) _known = _known.decline(declining);
      _waiting = true;
      _failure = null;
    });
    _toBottom();

    try {
      final turn = await widget.planner.intake(
        progress: _known,
        history: List<PlannerTurn>.unmodifiable(_turns),
      );
      if (!mounted) return;
      setState(() {
        // Merged, not replaced.
        _known = _known.merge(turn.extracted);
        _coachAsked = IntakeField.named(turn.asking);
        if (turn.reply.isNotEmpty) {
          _turns.add(PlannerTurn(text: turn.reply, fromCoach: true));
        }
        _waiting = false;
      });
    } on PlanException catch (e) {
      if (!mounted) return;
      // The question stays on screen: the failure is usually transient and the
      // obvious next action is to send the same thing again.
      setState(() {
        _waiting = false;
        _failure = e.failure;
      });
    }
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppMotion.base,
        curve: AppMotion.standard,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Backing out mid-turn abandons a call that has already been paid for, and
    // whose answer would have been merged into what the coach knows. The arrow
    // comes back the moment it lands.
    return PopScope(
      canPop: !_waiting,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Build a plan'),
          // Chrome, not conversation — see StepProgress. A coach that says
          // "question two of four" out loud is reading its own progress bar
          // aloud; the count belongs in the frame around the talking.
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              child: Center(
                child: StepProgress(
                  // Answers, not position: the bar is the count of fields
                  // settled, so one sentence covering three moves it three.
                  step: _known.answered,
                  total: _known.total,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: ConversationView(
                  controller: _scroll,
                  children: <Widget>[
                    for (final turn in _turns) ...<Widget>[
                      ConversationBubble(
                        text: turn.text,
                        fromCoach: turn.fromCoach,
                      ),
                      // Only under the newest turn, and only while the coach
                      // is not mid-answer. Options under an older message
                      // offer to answer a question that has been answered,
                      // and tapping one would send it as the reply to the
                      // latest thing said instead.
                      if (turn == _turns.last && !_waiting && _asking != null)
                        OptionStack(
                          options: _asking!.offered,
                          onSelected: (o) => _sendText(
                            o,
                            declining: o == _asking!.skip ? _asking : null,
                          ),
                        ),
                    ],
                    if (_waiting) const ThinkingIndicator(),
                    if (_failure != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Text(
                          _failure!.message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Appears the moment a block could be built, rather than waiting
              // for the coach to decide the conversation is over. Somebody who
              // has answered enough should not have to keep chatting to get out.
              if (_known.isComplete)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: PrimaryButton(
                    label: 'Build my plan',
                    onPressed: _waiting
                        ? null
                        : () => Navigator.of(context).pop(_known.plan),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: !_waiting,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Tell your coach',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.filled(
                      onPressed: _waiting ? null : _send,
                      icon: const Icon(Icons.arrow_upward),
                      tooltip: 'Send',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
