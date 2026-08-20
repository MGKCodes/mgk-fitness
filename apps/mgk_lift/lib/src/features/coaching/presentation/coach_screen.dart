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

  /// The value under the slider, while a turn is asking for one. Reset on every
  /// new ask, so the previous answer never becomes the next question's default.
  double? _asked;

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

  Future<void> _send() => _sendText(_input.text);

  /// Sends [raw], whether it was typed or tapped.
  ///
  /// A chip passes the coach's exact wording rather than a paraphrase of it —
  /// the transcript is what the coach replays, so a chip that sends something
  /// other than what it displayed would put a sentence nobody saw into it.
  Future<void> _sendText(String raw) async {
    final text = raw.trim();
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
    // **No Scaffold and no AppBar.** The coach is not a page any more — it is
    // the sheet that slides up over whichever of the three surfaces you were
    // on, so the chrome it needs is a drag handle rather than a title bar with
    // a back arrow to a place you never left. Material, because the composer is
    // a TextField and ink has to land somewhere.
    //
    // Transparent, because [CoachSheet] paints the photograph and the glass
    // behind this. A fill here would put an opaque sheet on top of the effect
    // and leave the blur doing nothing, which is exactly the no-op GlassSurface
    // warns about.
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            const SheetHandle(bottomSpacing: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  const SectionLabel('Coach'),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                    color: AppColors.textSecondary,
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
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
                        for (final turn in _turns) ...<Widget>[
                          // Keyed by the turn, so Entrance plays once when a
                          // message ARRIVES and never again — an un-keyed list
                          // reuses element state positionally and the whole
                          // conversation re-zooms every time somebody speaks.
                          Entrance(
                            key: ValueKey<String>(turn.id),
                            // Settling into place reads as something being
                            // said; a plain fade reads as something loading.
                            scaleFrom: 0.94,
                            offset: 8,
                            child: ConversationBubble(
                              text: turn.body,
                              fromCoach: turn.fromCoach,
                            ),
                          ),
                          // Only under the newest turn. Chips under an old
                          // message offer to answer a question that has already
                          // been answered, and tapping one would send it as
                          // though it were the reply to the latest thing said.
                          if (turn == _turns.last &&
                              !_waiting &&
                              turn.suggestions.isNotEmpty)
                            OptionStack(
                              options: turn.suggestions,
                              onSelected: _sendText,
                            ),
                          if (turn == _turns.last &&
                              !_waiting &&
                              turn.ask != null)
                            _AskField(
                              ask: turn.ask!,
                              value: _asked ?? turn.ask!.initial,
                              onChanged: (v) => setState(() => _asked = v),
                              onConfirm: () {
                                final v = _asked ?? turn.ask!.initial;
                                _asked = null;
                                _sendText(_render(turn.ask!, v));
                              },
                              // Declining is an answer, not a cancel. Age,
                              // height and weight are health data collected to
                              // build a plan, and a plan can be built without
                              // any of them -- worse, but built.
                              onSkip: () {
                                _asked = null;
                                _sendText('Prefer not to say');
                              },
                            ),
                        ],
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

/// What the lifter's answer reads as in the transcript.
///
/// The slider's number, said the way a person would say it — the coach replays
/// this later, and "82 kg" is a sentence where "82.0" is a reading off an
/// instrument.
String _render(CoachAsk ask, double v) => switch (ask.kind) {
  CoachAskKind.yearOfBirth => '${v.round()}',
  CoachAskKind.heightCm => '${v.round()} cm',
  CoachAskKind.weightKg => '${v.round()} kg',
};

/// One asked-for value, with its slider and its two ways out.
class _AskField extends StatelessWidget {
  const _AskField({
    required this.ask,
    required this.value,
    required this.onChanged,
    required this.onConfirm,
    required this.onSkip,
  });

  final CoachAsk ask;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onConfirm;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final (String label, String Function(int) format) = switch (ask.kind) {
      CoachAskKind.yearOfBirth => ('Year of birth', (v) => '$v'),
      CoachAskKind.heightCm => ('Height', (v) => '$v cm'),
      CoachAskKind.weightKg => ('Weight', (v) => '$v kg'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          WheelPicker(
            label: label,
            min: ask.min.round(),
            max: ask.max.round(),
            initial: value.round(),
            format: format,
            onChanged: (v) => onChanged(v.toDouble()),
            onSkip: onSkip,
          ),
          const SizedBox(height: AppSpacing.xs),
          PrimaryButton(label: 'That is me', onPressed: onConfirm),
        ],
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
