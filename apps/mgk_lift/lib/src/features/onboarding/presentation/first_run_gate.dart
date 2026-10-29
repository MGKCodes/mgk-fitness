import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/domain/account.dart';
import '../../auth/presentation/sign_in_screen.dart';
import '../domain/intro_store.dart';
import 'intro_screen.dart';
import 'welcome_screen.dart';

/// Where a cold start goes: the app, or, once per install, the welcome and the
/// coach's first lines in front of it (ADR-0005).
///
/// **In front of the shell, not inside it.** The shell starts work the moment
/// it is mounted (a backup checkpoint, the plan, the store), all of it for
/// somebody who is using the app, so it is not built until the intro is over.
/// The launch curtain is above the navigator and plays over whichever of the
/// two this opens on, so neither path changes how the app starts.
///
/// **Only a new install sees it.** Lift 2.0.0 had no intro, so on the first
/// launch after the update every existing lifter would read as new. Anybody
/// this phone already knows is let through and the intro is marked seen
/// without a word: a session restored at launch, or any training already on
/// the phone. The welcome is shown only on positive evidence of a new install
/// (nothing recorded, nothing logged, nobody signed in), so a check that
/// fails or takes too long opens the app rather than the welcome. A gate in
/// front of the app that guesses wrong in that direction costs six lines
/// somebody never read; guessing wrong in the other would stand a welcome
/// screen in front of somebody's training.
///
/// The welcome's two ways in both end on the intro. *Get started* goes
/// straight to it; *I already have an account* goes through Lift's sign-in
/// first, because a lifter arriving with an account made in Run has still
/// never opened Lift. Backing out of sign-in returns to the welcome.
class FirstRunGate extends StatefulWidget {
  const FirstRunGate({
    super.key,
    required this.store,
    required this.app,
    this.auth,
    this.hasTraining,
    this.readBudget = const Duration(seconds: 3),
  });

  /// Whether this install has met the intro.
  final IntroStore store;

  /// The app itself: what opens for everybody who has met the intro, and
  /// what *Start training* opens for everybody who has just met it.
  final Widget app;

  /// Signing in, from the welcome. **Null hides** *I already have an account*:
  /// a build with no server has no account to sign in to. Also read at launch,
  /// since a restored session is somebody upgrading.
  final AuthService? auth;

  /// Whether this phone already holds training. Null is a build with no
  /// database, which holds none. Asked only when the store says the intro
  /// has not been seen, which after the first launch is never.
  final Future<bool> Function()? hasTraining;

  /// How long a launch waits on either answer before opening the app.
  ///
  /// Both are reads off the phone and come back in a frame or two. This is
  /// for the read that never comes back, which would otherwise hold a blank
  /// screen up for good: the store's answer is then taken as "seen", and the
  /// phone's as "has training", which both open the app.
  final Duration readBudget;

  @override
  State<FirstRunGate> createState() => _FirstRunGateState();
}

/// Where the gate is.
enum _Arrival {
  /// The store is being read. A blank frame, under the launch curtain.
  reading,
  welcome,

  /// Sign-in is pushed over the welcome, which stays drawn underneath it so
  /// backing out returns to it.
  signingIn,
  intro,
  app,
}

class _FirstRunGateState extends State<FirstRunGate> {
  _Arrival _at = _Arrival.reading;

  /// Somebody opened sign-in from the welcome. An account arriving after that
  /// is theirs, not a restored session: see [_onAccount].
  bool _triedSignIn = false;

  /// The intro was reached by signing in, so it offers no way back: the
  /// welcome behind it would offer to sign in somebody who already has.
  bool _signedInHere = false;

  StreamSubscription<Account?>? _arrivals;

  @override
  void initState() {
    super.initState();
    _arrivals = widget.auth?.changes.listen(_onAccount);
    unawaited(_read());
  }

  @override
  void dispose() {
    unawaited(_arrivals?.cancel());
    super.dispose();
  }

  Future<void> _read() async {
    final seen = await _seen();
    final known = seen || await _usedBefore();
    if (!mounted || _at != _Arrival.reading) return;
    // Asked once more in the frame the decision is drawn in. A session
    // restored between the check above and now would otherwise put a lifter
    // who has used the app for months on the welcome; [_onAccount] covers the
    // moments after this one.
    final restored = widget.auth?.current != null;
    if (!seen && (known || restored)) unawaited(_markSeen());
    setState(() => _at = known || restored ? _Arrival.app : _Arrival.welcome);
  }

  /// The store's answer, or "seen" when it has none to give.
  Future<bool> _seen() => _ask(widget.store.hasSeen, otherwise: true);

  /// Whether this phone was in use before the intro existed: an account
  /// signed in, or training on it. Either answers for an upgrader; a phone
  /// that cannot say answers yes, for the reason on [FirstRunGate].
  Future<bool> _usedBefore() async {
    if (widget.auth?.current != null) return true;
    final check = widget.hasTraining;
    if (check == null) return false;
    return _ask(check, otherwise: true);
  }

  /// What [read] answers, or [otherwise] when it throws or has not answered
  /// within [FirstRunGate.readBudget].
  Future<bool> _ask(
    Future<bool> Function() read, {
    required bool otherwise,
  }) async {
    try {
      // **Re-made as a `Future<bool>` before the timeout**, which checks its
      // fallback against the future's own type. A read written as
      // `() async => throw ...` is a `Future<Never>`, which no fallback fits:
      // `timeout` would throw on the spot, the catch below would take that,
      // and the read's own error would go unheard, out to the zone as a crash
      // report. Found by this gate's own test of a phone it cannot read.
      return await read()
          .then<bool>((answer) => answer)
          .timeout(widget.readBudget, onTimeout: () => otherwise);
    } on Object {
      return otherwise;
    }
  }

  Future<void> _markSeen() async {
    try {
      await widget.store.markSeen();
    } on Object {
      // Shown again next launch, unless by then there is training here.
    }
  }

  /// An account arrived without the gate asking for it.
  ///
  /// **On the welcome, it is a session Supabase restored a moment late**, and
  /// so somebody who used 2.0.0 signed in: through to the app, as at launch.
  /// Unless they had opened sign-in already, in which case it is the account
  /// they were making (Apple's sign-in on Android finishes in the browser and
  /// can land after they have backed out), and they meet the intro.
  void _onAccount(Account? account) {
    if (account == null || !mounted || _at != _Arrival.welcome) return;
    if (_triedSignIn) {
      setState(() {
        _signedInHere = true;
        _at = _Arrival.intro;
      });
      return;
    }
    unawaited(_markSeen());
    setState(() => _at = _Arrival.app);
  }

  /// Lift's own sign-in, pushed over the welcome, as the shell pushes it.
  ///
  /// A route rather than a state of this widget, so back is the platform's
  /// own and lands on the welcome. It pops with true once somebody is signed
  /// in, after the name step a new account is asked.
  Future<void> _signIn() async {
    final auth = widget.auth;
    if (auth == null) return;
    setState(() {
      _triedSignIn = true;
      _at = _Arrival.signingIn;
    });
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => SignInScreen(auth: auth)),
    );
    if (!mounted || _at != _Arrival.signingIn) return;
    final arrived = signedIn == true || auth.current != null;
    setState(() {
      _signedInHere = arrived;
      _at = arrived ? _Arrival.intro : _Arrival.welcome;
    });
  }

  void _toWelcome() => setState(() => _at = _Arrival.welcome);

  /// *Start training*: the app, now, and the store told afterwards. The write
  /// is not waited on, so a slow plugin cannot hold somebody on a screen they
  /// have finished with.
  void _finish() {
    setState(() => _at = _Arrival.app);
    unawaited(_markSeen());
  }

  @override
  Widget build(BuildContext context) => switch (_at) {
    // Blank rather than a spinner, as Run's gate: a frame or two, under the
    // curtain, and a loader that flashes before a first impression reads as
    // a fault. Blank also means the welcome never flashes for somebody who
    // has seen it.
    _Arrival.reading => const Scaffold(body: SizedBox.shrink()),
    _Arrival.welcome || _Arrival.signingIn => WelcomeScreen(
      onGetStarted: () => setState(() => _at = _Arrival.intro),
      onHaveAccount: widget.auth == null ? null : () => unawaited(_signIn()),
    ),
    // The intro is a state of this widget, not a route, so the system back
    // gesture would find nothing to pop and leave the app from somebody's
    // second screen. Run's flow guards the same way.
    _Arrival.intro => PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_signedInHere) _toWelcome();
      },
      child: IntroScreen(
        onFinished: _finish,
        onBack: _signedInHere ? null : _toWelcome,
      ),
    ),
    _Arrival.app => widget.app,
  };
}
