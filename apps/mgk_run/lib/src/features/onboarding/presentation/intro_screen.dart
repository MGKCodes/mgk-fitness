import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../../coaching/presentation/scripted_conversation.dart';
import '../data/intro_permission_requester.dart';
import '../domain/intro_permission.dart';
import '../domain/intro_script.dart';

/// What the intro gathered, handed to sign-up.
///
/// Only a name now. It used to carry the plan shape as well, which then had to
/// survive the widget swap from the signed-out flow to the shell — see
/// `shape_question.dart` for why that question moved to the plan flow instead
/// (ADR-0019).
class IntroAnswers {
  const IntroAnswers({this.name, this.isFromIntro = false});

  /// Whether these came from the conversation rather than from nothing. The
  /// form uses it to decide whether it is creating an account or signing back
  /// into one, which a null name alone cannot say — the name is optional.
  final bool isFromIntro;

  final String? name;
}

/// Runio's first conversation, before there is an account.
///
/// It looks like the coach because it is the coach — the same voice, the same
/// left-aligned bubbles, the same mark beside them. It is scripted underneath
/// (see [introPrompt] for why), and the runner is never told a model answered.
///
/// The point is pedagogical: a runner's first act in Runio is talking to their
/// coach, so the coach never has to be found later. The form arrives last, as
/// something the coach asks for, rather than as a gate in front of everything.
///
/// This is **moment one** of two. It ends with a free account, granted
/// permissions and a working run tracker. Nothing here asks what the runner is
/// training for and nothing here mentions a price, because neither is relevant
/// until somebody wants a plan (ADR-0019).
class IntroScreen extends StatefulWidget {
  const IntroScreen({
    super.key,
    this.onFinished,
    this.onBack,
    this.initial = const IntroAnswers(),
    this.requestPermission = requestIntroPermission,
  });

  /// The conversation is over, carrying whatever the runner said to call them.
  ///
  /// The name travels out rather than being stored by this screen, because the
  /// intro no longer creates the account that used to hold it - see
  /// [IntroStore]. Null when they skipped the question.
  final void Function(String? name)? onFinished;

  /// What was already said, when the runner is coming *back* from the form.
  ///
  /// Without it the conversation restarted at "what should I call you?" every
  /// time they stepped back to change something — the exchange was still on the
  /// gate's state, but this widget is rebuilt fresh and its own step counter
  /// began again.
  final IntroAnswers initial;

  /// Back to the welcome screen.
  final VoidCallback? onBack;

  /// Raises the real OS dialog. Injected so the flow can be driven in a widget
  /// test, which has no platform to grant anything.
  final Future<bool> Function(IntroPermission permission) requestPermission;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _name = TextEditingController();
  final _scroll = ScrollController();

  late IntroStep _step = IntroStep.greeting;
  late String? _answeredName = widget.initial.name;

  /// The name was known before a word was said.
  ///
  /// True for a runner arriving from Lift: the name lives on the shared
  /// profile, so asking for it again would be this whole bug in miniature -
  /// treating a fact that belongs to the profile as one that belongs to this
  /// app. The step is skipped, and the transcript does not pretend to have
  /// asked.
  late final bool _knewName = widget.initial.name != null;

  /// Which permission is on screen. Only meaningful at [IntroStep.permissions].
  int _permissionIndex = 0;

  /// The permissions this platform can actually ask for, resolved once.
  ///
  /// Not `introPermissions` directly: Android has no Health Connect permissions
  /// in its manifest, so offering the Health step there produces a tap that
  /// silently resolves to "Not now" — the runner taps Allow and is told they
  /// declined. See `introPermissionsFor`.
  ///
  /// Read once into a field rather than called at each use, so the list cannot
  /// change length between `_afterName` deciding there is a step and
  /// `_afterPermission` deciding there is not.
  late final List<IntroPermission> _permissions = introPermissionsFor(
    defaultTargetPlatform,
  );

  /// What the OS said, per permission index. Absent means "not asked yet".
  final Map<int, bool> _outcomes = <int, bool>{};

  /// A dialog is up. The button goes busy so a second tap cannot stack two
  /// requests, which on Android surfaces as a prompt that will not dismiss.
  bool _asking = false;

  /// Turns that are in the transcript but have not been revealed yet.
  ///
  /// **This is the join between the screen's two clocks**, and its absence was
  /// the bug. The transcript is paced by [SequencedReveal], which lands one
  /// turn per beat off a `Timer`; the answer area was a plain `switch` on
  /// [_step] that rebuilt in the same frame as the tap. So tapping "Sounds
  /// good" queued "What should I call you?" a beat away while swapping in a
  /// `TextField` with `autofocus: true` immediately — the keyboard arrived
  /// ~620ms before the question it was there to answer. The very first frame
  /// had the same fault in miniature: [_step] starts at [IntroStep.greeting],
  /// so the button was painted before the greeting had been said at all.
  ///
  /// Counted as turns *pending* rather than turns *revealed* on purpose. A
  /// transcript that shrinks — [SequencedReveal] handles that case, so this
  /// must too — moves both ends of the comparison at once, and a delta clamped
  /// at zero stays correct where an absolute count would drift and hold the
  /// input back forever.
  late int _pending = _transcript().length;

  /// Opens the gate if the reveal never says it has caught up.
  ///
  /// See [_revealBudget]: the input must always arrive.
  Timer? _failsafe;

  /// The OS asked for less movement.
  ///
  /// [SequencedReveal] paints everything in one frame in that case and — since
  /// it never waits — never fires its `onRevealed` at all, so the gate would
  /// wait on a callback that is not coming. Asking the same question here is
  /// what stops that. Widget tests take this path too, which is why the flow
  /// tests still find their buttons on the frame they tap them.
  bool _reducedMotion = false;

  /// How long the gate will wait on one pending turn before opening itself.
  ///
  /// [SequencedReveal] beats at 620ms, so this is headroom rather than a race,
  /// and it is only ever reached when a reveal callback goes missing entirely.
  /// **The input must always arrive.** A gate whose only key is a callback is
  /// one dropped callback away from a runner stranded on a conversation with
  /// nothing to tap and no way back — a far worse failure than the mistimed
  /// keyboard the gate exists to fix.
  static const Duration _revealBudget = Duration(milliseconds: 900);

  /// Slack on top of [_revealBudget], so the failsafe cannot fire in the gap
  /// between the last beat landing and its callback being handled.
  static const Duration _revealSlack = Duration(seconds: 1);

  /// The height the answer area holds even while it is empty.
  ///
  /// Matches the primary button's minimum height in `AppTheme`. Without it the
  /// transcript lurches upward the moment the input arrives, and the gate ends
  /// up reading as the screen resizing rather than as the coach finishing
  /// their sentence.
  static const double _answerSlotHeight = 52;

  /// The last thing that went wrong, in the coach's voice.
  ///
  /// It is a line in the transcript rather than red text under a field,
  /// because on this screen there is no field to put it under and no reason to
  /// break character for it. Cleared on the next attempt so the conversation
  /// does not accumulate a list of everything the runner has mistyped.
  String? _trouble;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // The opening three turns are queued before any tap, so the failsafe has
    // to cover them too — a cold screen whose reveal never starts is the one
    // place a stranded runner could not even go back.
    _armFailsafe();
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    _name.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Whether the runner may answer yet.
  ///
  /// The input is held back until the turn it answers is on screen. Under
  /// reduced motion there is no wait to hold it back for.
  bool get _canAnswer => _reducedMotion || _pending == 0;

  /// The one way this screen changes what is in the transcript.
  ///
  /// Every mutation goes through here so the pending count cannot be forgotten
  /// at a call site added later: a `setState` that queues a turn without
  /// telling the gate would let the input back in a beat early, which is
  /// precisely the defect being fixed. Taking the length before and after also
  /// means no caller has to know *how many* turns their change produced —
  /// granting a permission adds two, and stepping into the permissions adds
  /// the prompt plus the first explanation.
  void _say(VoidCallback change) {
    final before = _transcript().length;
    setState(() {
      change();
      final after = _transcript().length;
      // Clamped at both ends: a shrinking transcript makes the delta negative,
      // and nothing can be pending that is not in the list.
      _pending = (_pending + after - before).clamp(0, after);
    });
    _armFailsafe();
    _toEnd();
  }

  /// A turn landed. One fewer thing between the runner and the input.
  void _onRevealed() {
    if (_pending > 0) setState(() => _pending--);
    _armFailsafe();
    _toEnd();
  }

  void _armFailsafe() {
    _failsafe?.cancel();
    _failsafe = null;
    if (_reducedMotion || _pending == 0) return;
    _failsafe = Timer(_revealBudget * _pending + _revealSlack, () {
      _failsafe = null;
      if (!mounted || _pending == 0) return;
      // The reveal has gone quiet with turns still queued. Better a question
      // answered slightly early than a screen that can no longer be left.
      setState(() => _pending = 0);
    });
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppMotion.base,
        curve: AppMotion.entrance,
      );
    });
  }

  void _advance(IntroStep to) => _say(() => _step = to);

  void _submitName() {
    // Anything is accepted. A name is not a format, and Settings is where a
    // mistyped one gets fixed.
    final given = _name.text.trim();
    _say(() {
      _answeredName = given.isEmpty ? null : given;
    });
    _afterName();
  }

  /// Where the conversation goes once the name is settled, however it was.
  void _afterName() {
    if (_permissions.isNotEmpty) {
      _advance(IntroStep.permissions);
      return;
    }
    // A build with nothing to ask for skips the step rather than rendering an
    // empty one. Not hypothetical: the list is one entry today and the whole
    // point of it being a list is that entries come and go. `_afterPermission`
    // is what knows where an intro with no account steps ends.
    _afterPermission();
  }

  Future<void> _ask() async {
    if (_asking) return;
    setState(() => _asking = true);
    final granted = await widget.requestPermission(
      _permissions[_permissionIndex],
    );
    if (!mounted) return;
    // Two turns at once: what the OS was told, and what the coach says back.
    _say(() {
      _outcomes[_permissionIndex] = granted;
      _asking = false;
    });
  }

  void _afterPermission() {
    if (_permissionIndex + 1 < _permissions.length) {
      _say(() => _permissionIndex++);
      return;
    }
    // **The intro ends here, and no longer hands off to an account.**
    //
    // It used to ask for an address and a password as two more turns, on the
    // reasoning that a conversation ending in a pushed form has not avoided the
    // form. That reasoning was right about forms and wrong about the account:
    // the cheapest sign-up is the one not asked for. Everything this screen
    // exists to do - meet the coach, get the permissions a tracker needs - is
    // done, and the app works from here with nothing signed in.
    //
    // An account is asked for where it buys something: a plan, and backup.
    widget.onFinished?.call(_answeredName);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: widget.onBack == null
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              leading: BackButton(onPressed: widget.onBack),
            ),
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/onboarding.jpg',
        opacity: 0.34,
        scrim: ScrimStrength.grounded,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              // **Grows from the bottom.** A `ListView` anchors its children to
              // the top, which meant the first three screens of the app were a
              // short exchange stranded under the app bar with a button pinned
              // half a phone away and nothing in between. A conversation
              // accumulates upward from where you are typing, so a scroll view
              // whose column is bottom-aligned when it underfills reads right
              // at every length: the newest line always sits just above the
              // answer, and once the transcript outgrows the screen this
              // behaves exactly like the list it replaced.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.lg,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        // Minus the padding this view already adds, or the
                        // column is taller than the space it is measuring
                        // against and the view scrolls when it has no need to.
                        minHeight:
                            constraints.maxHeight -
                            AppSpacing.xl -
                            AppSpacing.lg,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // **The pacing is the content.** These five bubbles
                          // used to paint in a single frame, so the first
                          // screen of the app — the one whose whole job is to
                          // feel like meeting a coach — read as a form that had
                          // already filled itself in. A conversation arrives a
                          // line at a time, with somebody composing in between.
                          SequencedReveal(
                            onRevealed: _onRevealed,
                            children: _transcript(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                // **The whole conversation is one autofill context.** The
                // address and the password are asked a step apart, so without
                // a group spanning both the platform sees two unrelated fields
                // and offers to save neither.
                child: AutofillGroup(
                  // **Nothing at all until the question has been asked.** Not
                  // a disabled control and not a hidden one: a `TextField`
                  // that is merely invisible still takes `autofocus`, and the
                  // keyboard rising ahead of the question is the whole defect.
                  // The slot keeps its height either way so the transcript
                  // does not jump when the input turns up.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: _answerSlotHeight,
                    ),
                    child: _canAnswer
                        ? _answer(theme)
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The conversation so far, oldest turn first.
  ///
  /// Lifted out of `build` because the input gate needs to *count* it, not
  /// just draw it: [_say] takes its length before and after every change to
  /// work out how many turns are now queued behind a beat. Derived from the
  /// step counter rather than accumulated, so a rebuild cannot duplicate a
  /// turn and stepping back cannot leave an orphan on screen.
  List<Widget> _transcript() {
    final reached = _step.index;
    return <Widget>[
      Said(introPrompt(IntroStep.greeting)),
      Said(introWhoIAm),
      Said(introHowItWorks),
      if (!_knewName && reached >= IntroStep.name.index)
        Said(introPrompt(IntroStep.name)),
      if (!_knewName && _answeredName != null) Replied(_answeredName!),
      if (reached >= IntroStep.permissions.index) ...<Widget>[
        Said(introPrompt(IntroStep.permissions, name: _answeredName)),
        ..._permissionTranscript(),
      ],
      if (_trouble != null) Said(_trouble!),
    ];
  }

  /// Every permission asked so far: what it was for, what they answered, and
  /// what the coach said back.
  ///
  /// Past the permissions step this shows all of them, so a runner who reaches
  /// the form can still scroll up and see what they agreed to.
  List<Widget> _permissionTranscript() {
    final last = _step.index > IntroStep.permissions.index
        ? _permissions.length - 1
        : _permissionIndex;
    return <Widget>[
      for (var i = 0; i <= last && i < _permissions.length; i++) ...<Widget>[
        Said(_permissions[i].explain),
        if (_outcomes[i] != null) ...<Widget>[
          // The runner did not type this, they answered a system dialog — but
          // showing it as their turn keeps the screen a conversation rather
          // than a form with a log stapled underneath.
          Replied(_outcomes[i]! ? 'Allowed' : 'Not now'),
          Said(
            _outcomes[i]! ? _permissions[i].granted : _permissions[i].denied,
          ),
        ],
      ],
    ];
  }

  Widget _answer(ThemeData theme) => switch (_step) {
    IntroStep.greeting => PrimaryButton(
      label: 'Sounds good',
      onPressed: _knewName ? _afterName : () => _advance(IntroStep.name),
    ),

    IntroStep.name => Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitName(),
            decoration: const InputDecoration(
              hintText: 'Your name',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        IconButton.filled(
          onPressed: _submitName,
          icon: const Icon(Icons.arrow_forward),
          tooltip: 'Continue',
        ),
      ],
    ),

    IntroStep.permissions =>
      _outcomes[_permissionIndex] == null
          ? PrimaryButton(
              label: _permissions[_permissionIndex].cta,
              busy: _asking,
              onPressed: _ask,
            )
          : PrimaryButton(label: 'Continue', onPressed: _afterPermission),
  };
}
