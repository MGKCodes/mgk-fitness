import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/plan_intake.dart';
import '../domain/coach_planner.dart';

/// The conversation that sets a block up.
///
/// **A conversation rather than a form**, which is the point and also the
/// harder thing to build: a form asks six questions in a fixed order and makes
/// somebody who answered three of them in one sentence answer them again. The
/// coach batches, skips ahead, and stops when it has enough.
///
/// What it gathers is merged, never replaced. Every intake turn returns every
/// field, and a null means "not learned this turn" — treating it as "forget it"
/// would erase an answer as soon as the next question was asked.
class PlanIntakeScreen extends StatefulWidget {
  const PlanIntakeScreen({
    super.key,
    required this.planner,
    this.opener,
    this.initialTurns = const <PlannerTurn>[],
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

  @override
  State<PlanIntakeScreen> createState() => _PlanIntakeScreenState();
}

class _PlanIntakeScreenState extends State<PlanIntakeScreen> {
  final List<PlannerTurn> _turns = <PlannerTurn>[];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  PlanIntake _known = const PlanIntake();
  bool _waiting = false;
  PlanFailure? _failure;

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
    if (text.isEmpty || _waiting) return;

    setState(() {
      _turns.add(PlannerTurn(text: text, fromCoach: false));
      _input.clear();
      _waiting = true;
      _failure = null;
    });
    _toBottom();

    try {
      final turn = await widget.planner.intake(
        known: _known,
        history: List<PlannerTurn>.unmodifiable(_turns),
      );
      if (!mounted) return;
      setState(() {
        // Merged, not replaced.
        _known = _known.merge(turn.extracted);
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
        appBar: AppBar(title: const Text('Build a plan')),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: ConversationView(
                  controller: _scroll,
                  children: <Widget>[
                    for (final turn in _turns)
                      ConversationBubble(
                        text: turn.text,
                        fromCoach: turn.fromCoach,
                      ),
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
                        : () => Navigator.of(context).pop(_known),
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
