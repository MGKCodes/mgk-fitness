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
    required this.onDone,
    this.onBack,
    this.initial = const IntroAnswers(),
    this.requestPermission = requestIntroPermission,
  });

  /// What was already said, when the runner is coming *back* from the form.
  ///
  /// Without it the conversation restarted at "what should I call you?" every
  /// time they stepped back to change something — the exchange was still on the
  /// gate's state, but this widget is rebuilt fresh and its own step counter
  /// began again.
  final IntroAnswers initial;

  /// Called with what was gathered when the runner is ready to make an account.
  final void Function(IntroAnswers answers) onDone;

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

  late IntroStep _step = widget.initial.isFromIntro
      ? IntroStep.signUp
      : IntroStep.greeting;
  late String? _answeredName = widget.initial.name;

  /// Which permission is on screen. Only meaningful at [IntroStep.permissions].
  int _permissionIndex = 0;

  /// What the OS said, per permission index. Absent means "not asked yet".
  final Map<int, bool> _outcomes = <int, bool>{};

  /// A dialog is up. The button goes busy so a second tap cannot stack two
  /// requests, which on Android surfaces as a prompt that will not dismiss.
  bool _asking = false;

  @override
  void dispose() {
    _name.dispose();
    _scroll.dispose();
    super.dispose();
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

  void _advance(IntroStep to) {
    setState(() => _step = to);
    _toEnd();
  }

  void _submitName() {
    // Anything is accepted. A name is not a format, and Settings is where a
    // mistyped one gets fixed.
    final given = _name.text.trim();
    setState(() {
      _answeredName = given.isEmpty ? null : given;
      // A build with nothing to ask for skips the step rather than rendering an
      // empty one. Not hypothetical: the list is one entry today and the whole
      // point of it being a list is that entries come and go.
      _step = introPermissions.isEmpty
          ? IntroStep.signUp
          : IntroStep.permissions;
    });
    _toEnd();
  }

  Future<void> _ask() async {
    if (_asking) return;
    setState(() => _asking = true);
    final granted = await widget.requestPermission(
      introPermissions[_permissionIndex],
    );
    if (!mounted) return;
    setState(() {
      _outcomes[_permissionIndex] = granted;
      _asking = false;
    });
    _toEnd();
  }

  void _afterPermission() {
    if (_permissionIndex + 1 < introPermissions.length) {
      setState(() => _permissionIndex++);
      _toEnd();
      return;
    }
    _advance(IntroStep.signUp);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reached = _step.index;

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
                          Said(introPrompt(IntroStep.greeting)),
                          Said(introWhoIAm),
                          Said(introHowItWorks),
                          if (reached >= IntroStep.name.index)
                            Said(introPrompt(IntroStep.name)),
                          if (_answeredName != null) Replied(_answeredName!),
                          if (reached >=
                              IntroStep.permissions.index) ...<Widget>[
                            Said(
                              introPrompt(
                                IntroStep.permissions,
                                name: _answeredName,
                              ),
                            ),
                            ..._permissionTranscript(),
                          ],
                          if (_step == IntroStep.signUp)
                            Said(introPrompt(IntroStep.signUp)),
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
                child: _answer(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Every permission asked so far: what it was for, what they answered, and
  /// what the coach said back.
  ///
  /// Past the permissions step this shows all of them, so a runner who reaches
  /// the form can still scroll up and see what they agreed to.
  List<Widget> _permissionTranscript() {
    final last = _step.index > IntroStep.permissions.index
        ? introPermissions.length - 1
        : _permissionIndex;
    return <Widget>[
      for (
        var i = 0;
        i <= last && i < introPermissions.length;
        i++
      ) ...<Widget>[
        Said(introPermissions[i].explain),
        if (_outcomes[i] != null) ...<Widget>[
          // The runner did not type this, they answered a system dialog — but
          // showing it as their turn keeps the screen a conversation rather
          // than a form with a log stapled underneath.
          Replied(_outcomes[i]! ? 'Allowed' : 'Not now'),
          Said(
            _outcomes[i]!
                ? introPermissions[i].granted
                : introPermissions[i].denied,
          ),
        ],
      ],
    ];
  }

  Widget _answer(ThemeData theme) => switch (_step) {
    IntroStep.greeting => PrimaryButton(
      label: 'Sounds good',
      onPressed: () => _advance(IntroStep.name),
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
              label: introPermissions[_permissionIndex].cta,
              busy: _asking,
              onPressed: _ask,
            )
          : PrimaryButton(label: 'Continue', onPressed: _afterPermission),

    IntroStep.signUp => PrimaryButton(
      label: 'Create my account',
      onPressed: () =>
          widget.onDone(IntroAnswers(name: _answeredName, isFromIntro: true)),
    ),
  };
}
