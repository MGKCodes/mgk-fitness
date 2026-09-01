import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../legal/domain/legal_copy.dart';
import '../../legal/presentation/legal_document_screen.dart';
import '../domain/coach.dart';
import 'coach_history_sheet.dart';

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
    this.massUnit = MassUnit.kilograms,
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

  /// What the lifter works in. Only the asked-for values read it — height and
  /// weight are offered in the system they already use everywhere else, and
  /// height follows the mass unit rather than carrying a preference of its own.
  final MassUnit massUnit;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> with WidgetsBindingObserver {
  final List<CoachTurn> _turns = <CoachTurn>[];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _waiting = false;
  CoachFailure? _failure;
  int _counter = 0;

  /// Where the newest turn sits in a counted sequence, if it is in one.
  (int, int)? get _progress {
    if (_turns.isEmpty) return null;
    final t = _turns.last;
    final step = t.step;
    final total = t.stepsTotal;
    if (step == null || total == null) return null;
    return (step, total);
  }

  /// The value under the slider, while a turn is asking for one. Reset on every
  /// new ask, so the previous answer never becomes the next question's default.
  double? _asked;

  /// True until the stored conversation has been read, so the screen does not
  /// flash its empty state — "It has read your log" — at somebody who has been
  /// talking to it for a month.
  bool _resuming = false;

  /// The session every turn on screen belongs to.
  ///
  /// Null until something is said, which is what makes a boundary free: a
  /// screen opened and closed without a word writes no conversation at all.
  String? _conversationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final transcript = widget.transcript;
    if (transcript != null) {
      _resuming = true;
      _resume(transcript);
      return;
    }
    _addOpener();
  }

  /// The session boundary, applied on the way back in.
  ///
  /// **The gap decides, not the fact of having been away.** Ten seconds in the
  /// notification centre is not a new conversation; a session in the gym is.
  /// Nothing is torn down here — the turns stay on screen, because a
  /// transcript vanishing while somebody looks at it is a worse surprise than
  /// the coach starting fresh. What changes is where the next thing said goes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _turns.isEmpty ? null : _turns.last.at;
    if (last == null) return;
    if (DateTime.now().difference(last) <= coachSessionWindow) return;
    _conversationId = null;
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
    // Which conversation, before what is in it. A conversation whose last turn
    // is outside the window is not restored at all — that is the whole of the
    // session boundary on a cold start, and it is why this asks "what is open"
    // rather than "what was last said in".
    final open = await transcript.openConversationId();
    final stored = open == null
        ? const <CoachTurn>[]
        : await transcript.read(open);
    if (!mounted) return;
    _conversationId = open;
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
    WidgetsBinding.instance.removeObserver(this);
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
  ///
  /// [startsSession] is true for a question the lifter did not type. A
  /// suggestion chip is a subject the *screen* raised, and it arrives with its
  /// own topic: continuing into it is how a half-finished exchange about a sore
  /// shoulder becomes the context for "how has my training been going". The
  /// wheel under a question is not one of these — it is the answer to what was
  /// just asked, and belongs to the conversation asking it.
  Future<void> _sendText(String raw, {bool startsSession = false}) async {
    final text = raw.trim();
    if (text.isEmpty || _waiting) return;

    if (startsSession) _conversationId = null;
    final conversation = _conversationId ??= newCoachConversationId();

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
      final reply = await widget.coach.ask(text, conversationId: conversation);
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

  /// The turns, the thinking indicator and whatever the newest turn is
  /// asking for. Lifted out of build so the top bar can be stacked over it.
  Widget _conversation(BuildContext context) {
    return _resuming && _turns.isEmpty
        // Bounded by SupabaseCoachTranscript.requestTimeout, which is
        // what keeps this from becoming a spinner nobody can leave.
        // The composer below stays live throughout.
        ? const Center(child: CircularProgressIndicator())
        : _turns.isEmpty && !_waiting
        ? const _Empty()
        : ConversationView(
            controller: _scroll,
            // Room for the bar stacked over this. Without it the
            // first turn opens already underneath the blur.
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              _TopBar.height,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
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
                    onSelected: (String o) => _sendText(o, startsSession: true),
                  ),
                if (turn == _turns.last && !_waiting && turn.ask != null)
                  _AskField(
                    ask: turn.ask!,
                    massUnit: widget.massUnit,
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
          );
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
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: _conversation(context)),
                  // **The bar floats over the conversation, and blurs it.**
                  //
                  // Laid out above the list, the bar cut the topmost bubble
                  // dead along a straight edge — text simply stopped, mid-word,
                  // against a hard line. Content passing UNDER a blurred bar is
                  // what makes a scroll read as continuing past the chrome
                  // rather than being clipped by it.
                  //
                  // The list carries matching top padding, so nothing is
                  // permanently hidden: the first turn starts below the bar and
                  // only travels under it once there is more than a screenful.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _TopBar(
                      progress: _progress,
                      // Only where there is somewhere to look. With no
                      // transcript wired there are no past conversations, and
                      // a control that opens an empty list is a promise the
                      // app cannot keep.
                      onHistory: widget.transcript == null
                          ? null
                          : () => PastConversationsSheet.show(
                              context,
                              transcript: widget.transcript!,
                              liveConversationId: _conversationId,
                            ),
                      onClose: () => Navigator.of(context).maybePop(),
                    ),
                  ),
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

/// `69` inches as `5' 9"`.
///
/// A single wheel of inches rather than two of feet and inches: two drums for
/// one measurement doubles the chrome to save nobody any scrolling, and the
/// combined value is what gets stored either way.
String _feetInches(int inches) => "${inches ~/ 12}' ${inches % 12}\"";

/// One asked-for value, with its wheel and its two ways out.
class _AskField extends StatelessWidget {
  const _AskField({
    required this.ask,
    required this.massUnit,
    required this.value,
    required this.onChanged,
    required this.onConfirm,
    required this.onSkip,
  });

  final CoachAsk ask;

  /// What the lifter works in. Height follows it — see build.
  final MassUnit massUnit;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onConfirm;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    // **Imperial follows the mass unit**, rather than carrying a preference of
    // its own. Somebody who weighs in pounds measures height in feet; a third
    // setting for the pairing would be a question nobody wants asked, and a way
    // for the two halves of one body to disagree.
    final imperial = massUnit == MassUnit.pounds;

    final (
      String label,
      int min,
      int max,
      int initial,
      String Function(int) fmt,
    ) = switch (ask.kind) {
      // A year is a year in both systems.
      CoachAskKind.yearOfBirth => (
        'Year of birth',
        ask.min.round(),
        ask.max.round(),
        ask.initial.round(),
        (v) => '$v',
      ),
      // **The wheel steps in the DISPLAY unit, not the stored one.** Over
      // centimetres, an imperial reader gets a drum where two or three rows
      // in a row read as the same inches -- the value stalls under a moving
      // finger, which is exactly the failure the wheel replaced a slider to
      // avoid.
      CoachAskKind.heightCm =>
        imperial
            ? ('Height', 51, 87, 69, _feetInches)
            : (
                'Height',
                ask.min.round(),
                ask.max.round(),
                ask.initial.round(),
                (v) => '$v cm',
              ),
      CoachAskKind.weightKg =>
        imperial
            ? ('Weight', 80, 440, 176, (v) => '$v lb')
            : (
                'Weight',
                ask.min.round(),
                ask.max.round(),
                ask.initial.round(),
                (v) => '$v kg',
              ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          WheelPicker(
            label: label,
            min: min,
            max: max,
            initial: initial,
            format: fmt,
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

/// The sheet's chrome: a handle, the label, how far through, and a way out.
///
/// **Blurred, with the conversation running under it.** Laid out above the
/// list, this cut the topmost bubble along a straight edge and text stopped
/// mid-word against a hard line. A bar that frosts what passes behind it is
/// what makes the scroll read as continuing past the chrome rather than being
/// clipped by it — and it is the one piece of this sheet where the iOS
/// convention is simply right.
///
/// The fade below the blur matters as much as the blur. A blurred band with a
/// hard bottom edge is still an edge; letting it dissolve over the last few
/// pixels is what stops the boundary being a line.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.progress,
    required this.onHistory,
    required this.onClose,
  });

  final (int, int)? progress;

  /// Opens the previous conversations, or null when there is no store to read
  /// them from.
  final VoidCallback? onHistory;

  final VoidCallback onClose;

  /// Mirrored into the list's top padding, so the first turn opens below the
  /// bar rather than already under it.
  static const double height = 64;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              AppColors.bg.withValues(alpha: 0.55),
              AppColors.bg.withValues(alpha: 0.28),
              AppColors.bg.withValues(alpha: 0),
            ],
            stops: const <double>[0, 0.65, 1],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SheetHandle(bottomSpacing: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  const SectionLabel('Coach'),
                  const Spacer(),
                  if (progress != null) ...<Widget>[
                    StepProgress(step: progress!.$1, total: progress!.$2),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  // Hidden mid-questionnaire: the intake is a sequence with an
                  // end, and offering a way into old conversations part-way
                  // through it is an invitation to abandon one.
                  if (onHistory != null && progress == null)
                    AppIconButton(
                      onPressed: onHistory,
                      icon: Icons.history,
                      size: 20,
                      color: AppColors.textSecondary,
                      tooltip: 'Previous conversations',
                      visualDensity: VisualDensity.compact,
                    ),
                  // The disclosure, at the point of use (Guideline 5.1.2(i)).
                  // Settings carries it too, but this is the screen that does
                  // the sending, and a disclosure somebody has to go looking
                  // for in another tab is one they will not read.
                  //
                  // Shown mid-intake as well, unlike history: the questionnaire
                  // is where the injury notes are typed, so it is the last
                  // moment the answer is worth having.
                  AppIconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const LegalDocumentScreen(document: aiDisclosure),
                      ),
                    ),
                    icon: Icons.info_outline,
                    size: 20,
                    color: AppColors.textSecondary,
                    tooltip: aiDisclosure.title,
                    visualDensity: VisualDensity.compact,
                  ),
                  AppIconButton(
                    onPressed: onClose,
                    icon: Icons.close,
                    size: 20,
                    color: AppColors.textSecondary,
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
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
