import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/coach.dart';

/// The conversation.
///
/// **Kept for the session only.** `coach.conversations` and `coach.turns` exist
/// server-side and are where this belongs, but persisting a conversation is a
/// bigger decision than it looks — it is a record of somebody discussing their
/// body and their injuries, and it should not start being kept as a side effect
/// of a chat screen shipping. Wiring it is a deliberate follow-up.
///
/// Session-only is not the same as turn-only, though: what is on screen is sent
/// with each message, so the coach follows the thread within a visit. What it
/// does not do is remember the last one.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key, required this.coach, this.opener});

  final CoachService coach;

  /// A first line from the coach, so the screen is not an empty box with a
  /// cursor in it.
  final String? opener;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final List<CoachTurn> _turns = <CoachTurn>[];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _waiting = false;
  CoachFailure? _failure;
  int _counter = 0;

  @override
  void initState() {
    super.initState();
    final opener = widget.opener;
    if (opener != null) {
      _turns.add(
        CoachTurn(
          id: 'opener',
          body: opener,
          fromCoach: true,
          at: DateTime.now(),
        ),
      );
    }
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

    // Taken before the new turn is added, because the coach is sent the
    // conversation SO FAR plus the message — sending it twice would have the
    // lifter appear to say the same thing to itself.
    final history = List<CoachTurn>.unmodifiable(_turns);

    setState(() {
      _turns.add(
        CoachTurn(
          id: 'u${++_counter}',
          body: text,
          fromCoach: false,
          at: DateTime.now(),
        ),
      );
      _input.clear();
      _waiting = true;
      _failure = null;
    });
    _toBottom();

    try {
      final reply = await widget.coach.ask(text, history: history);
      if (!mounted) return;
      setState(() {
        _turns.add(
          CoachTurn(
            id: 'c${++_counter}',
            body: reply,
            fromCoach: true,
            at: DateTime.now(),
          ),
        );
        _waiting = false;
      });
    } on CoachException catch (e) {
      if (!mounted) return;
      // The question stays on screen. Removing it would lose what they typed,
      // and the failure is nearly always transient - the obvious next action is
      // to send the same thing again.
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Coach')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: _turns.isEmpty && !_waiting
                  ? const _Empty()
                  // Bottom-anchored: a short conversation sits against the
                  // composer and grows upward, rather than one bubble floating
                  // above a screen of nothing. A plain ListView top-anchors,
                  // and `Spacer` cannot help inside one - a scrollable has no
                  // bounded main axis to distribute.
                  : LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight:
                                constraints.maxHeight - AppSpacing.lg * 2,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              for (final turn in _turns) _Bubble(turn: turn),
                              if (_waiting) const _Thinking(),
                              // Attached to the message it refers to, not
                              // stranded at the bottom of the screen with the
                              // question at the top.
                              if (_failure != null)
                                _Failure(failure: _failure!),
                            ],
                          ),
                        ),
                      ),
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
                        hintText: 'Ask your coach',
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
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'It has read your log',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              // Concrete openers, because "ask me anything" is the least
              // useful prompt in software.
              'Ask why a lift has stalled, what to do about a sore shoulder, '
              'or whether this week was enough.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn});

  final CoachTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: turn.fromCoach
            ? Alignment.centerLeft
            : Alignment.centerRight,
        child: ConstrainedBox(
          // Never full width. A bubble that reaches both margins stops reading
          // as one side of a conversation.
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: turn.fromCoach ? AppColors.elevated : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: SelectableText(
                turn.body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: turn.fromCoach
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Why the last message got no answer, next to the message.
class _Failure extends StatelessWidget {
  const _Failure({required this.failure});

  final CoachFailure failure;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Text(
      failure.message,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
    ),
  );
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(
        'Thinking…',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
      ),
    ),
  );
}
