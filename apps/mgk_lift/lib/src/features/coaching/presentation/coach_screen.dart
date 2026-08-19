import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/coach.dart';

/// The conversation.
///
/// **What is on screen is what the coach remembers.** The server has always
/// kept the transcript and replayed it — that is why the coach follows a thread
/// across visits and across devices — but until [transcript] existed the screen
/// drew only what it had seen since it opened. Reopening the app gave an empty
/// screen and a coach that still knew you, which is a strange thing to hand
/// somebody: it invites them to re-explain an injury they already described,
/// and it makes the coach look like it invented the context it then uses.
///
/// The two now show the same window deliberately, not incidentally. See
/// [CoachTranscript.read] for why matching the replayed window beats showing
/// everything ever said.
///
/// **Nothing new is stored to make this work.** The rows already existed; this
/// only reads them back. What the coach keeps, and how to erase it, is Settings
/// → Coach, which the empty state points at before a first message rather than
/// after.
class CoachScreen extends StatefulWidget {
  const CoachScreen({
    super.key,
    required this.coach,
    this.transcript,
    this.opener,
  });

  final CoachService coach;

  /// What was said before. **Null means this build cannot resume** — a preview,
  /// a test, or a signed-out session — and the screen opens on its empty state
  /// exactly as it always did.
  final CoachTranscript? transcript;

  /// A first line from the coach, so the screen is not an empty box with a
  /// cursor in it.
  ///
  /// **Ignored once there is a transcript to show.** Appended after a real
  /// conversation it would read as something the coach just said; placed before
  /// one it would rewrite how the conversation started. An opener is for an
  /// empty screen, which is the only place it is now used.
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

  /// True until the stored conversation has been read, so the screen does not
  /// flash its empty state — "It has read your log" — at somebody who has been
  /// talking to it for a month.
  bool _resuming = false;

  @override
  void initState() {
    super.initState();
    final transcript = widget.transcript;
    if (transcript != null) {
      _resuming = true;
      _resume(transcript);
      return;
    }
    _addOpener();
  }

  /// Draws the stored conversation, then scrolls to the end of it.
  ///
  /// [CoachTranscript.read] does not throw, so there is no failure branch here:
  /// a transcript that would not load arrives as an empty list and the screen
  /// opens the way it does for somebody new. That is the right fallback — the
  /// composer never depended on this, and refusing to show a screen because its
  /// history is unavailable would break the working half to report the broken
  /// one.
  Future<void> _resume(CoachTranscript transcript) async {
    final stored = await transcript.read();
    if (!mounted) return;
    setState(() {
      // **Inserted at the front, not appended.** The composer stays live while
      // this runs, so a lifter can ask something before the history arrives —
      // and appending would then file the old conversation underneath the
      // question they just asked, which reads as the coach answering first.
      _turns.insertAll(0, stored);
      _resuming = false;
      if (_turns.isEmpty) _addOpener();
    });
    // Opening at the top of a long conversation would bury the composer and
    // the most recent thing said. The newest turn is the one being answered.
    if (stored.isNotEmpty) _toBottom();
  }

  void _addOpener() {
    final opener = widget.opener;
    if (opener == null) return;
    _turns.add(
      CoachTurn(
        id: 'opener',
        body: opener,
        fromCoach: true,
        at: DateTime.now(),
      ),
    );
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
      final reply = await widget.coach.ask(text);
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
              child: _resuming && _turns.isEmpty
                  // Bounded by SupabaseCoachTranscript.requestTimeout, which is
                  // what keeps this from becoming a spinner nobody can leave.
                  // The composer below stays live throughout.
                  ? const Center(child: CircularProgressIndicator())
                  : _turns.isEmpty && !_waiting
                  ? const _Empty()
                  : ConversationView(
                      controller: _scroll,
                      children: <Widget>[
                        for (final turn in _turns)
                          ConversationBubble(
                            text: turn.body,
                            fromCoach: turn.fromCoach,
                          ),
                        if (_waiting) const ThinkingIndicator(),
                        // Attached to the message it refers to, not stranded at
                        // the bottom of the screen with the question at the top.
                        if (_failure != null) _Failure(failure: _failure!),
                      ],
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
            const SizedBox(height: AppSpacing.lg),
            Text(
              // Said before the first message rather than discovered later.
              // The coach keeps notes about somebody's training and their
              // body; a lifter who has not been told that cannot decide what
              // to tell it. Settings is where they can read and clear it.
              'It also remembers you between conversations. Settings shows '
              'exactly what it has kept, and clears it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
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
