import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../coaching/data/coach_client.dart';
import '../../coaching/data/plan_client.dart';
import '../../coaching/data/coach_memory_store.dart';
import '../../history/domain/run_writer.dart';
import '../../settings/domain/backup_consent.dart';
import '../../settings/domain/backup_health.dart';
import '../../coaching/data/plan_store.dart';
import '../../coaching/data/entitlement_repository.dart';
import '../../coaching/data/purchase_client.dart';
import '../../coaching/data/revenuecat_purchases.dart';
import '../../home/presentation/home_shell.dart';
import '../../settings/domain/unit_settings.dart';
import '../../onboarding/data/intro_permission_requester.dart';
import '../../onboarding/data/intro_store_factory.dart';
import '../../onboarding/domain/intro_store.dart';
import '../../onboarding/domain/intro_permission.dart';
import '../../onboarding/presentation/welcome_screen.dart';
import '../../recording/domain/run_recorder.dart';
import '../../recording/domain/run_summary.dart';
import '../data/auth_repository.dart';
import '../../onboarding/presentation/intro_screen.dart';
import '../../settings/data/backup_eraser.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'sign_in_screen.dart';

/// Routes between the sign-in flow and the app shell based on auth state.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    this.auth = const AuthRepository(),
    this.devAccounts,
    this.recorderFactory,
    this.historySource,
    this.runEditor,
    this.restore,
    this.consentStore,
    this.backupHealth,
    this.eraser,
    this.coach,
    this.planClient,
    this.planStore,
    this.planBackup,
    this.memoryStore,
    this.memoryMirror,
    this.unitSettings,
    this.entitlements,
    this.purchases,
    this.requestPermission,
    this.introStore,
    this.localData,
  });

  final AuthRepository auth;

  /// Raises the intro's OS permission dialogs. Null uses the real one. Injected
  /// only so widget tests can drive both answers; there is no platform in a
  /// test to grant anything, and the outcome changes what the coach says next.
  final Future<bool> Function(IntroPermission permission)? requestPermission;

  /// Developer quick-sign-in accounts to offer on the sign-in screen. Defaults
  /// to the local config's accounts in debug builds (none in release). The
  /// preview harness injects fakes here to exercise the flow without a backend.
  final List<DevAccount>? devAccounts;

  /// Forwarded to [HomeShell] — the real app supplies the device-backed
  /// recorder / history data and the coach; the preview supplies fakes.
  final RunRecorder Function()? recorderFactory;
  final Future<List<RunSummary>> Function()? historySource;

  /// Adds and corrects runs. Forwarded straight to the shell.
  final RunWriter? runEditor;

  /// Pulls a reinstalled or new phone's data back down. Forwarded to the shell,
  /// which runs it once before its first load.
  final DataRestore? restore;

  /// Where the backup answer lives, so the shell can ask once before it pulls.
  final BackupConsentStore? consentStore;

  /// Forwarded to the shell for Profile's backup line.
  final BackupHealthStore? backupHealth;

  /// Removes what is already stored when consent is withdrawn.
  final BackupErasure? eraser;
  final CoachClient? coach;
  final PlanClient? planClient;
  final PlanStore? planStore;
  final PlanBackup? planBackup;

  /// Where the coach's memory lives — its transcript and rolling summary.
  final CoachMemoryStore? memoryStore;
  final CoachMemoryMirror? memoryMirror;

  /// Where the display unit is read and written.
  final UnitSettings? unitSettings;

  /// Injectable so a test can pin a tier without a Supabase session. The app
  /// leaves it null and gets [SupabaseEntitlements].
  final EntitlementRepository? entitlements;

  /// Forwarded to [HomeShell]. Null in the real app means "make one", not
  /// "cannot sell" -- see [_AuthGateState._purchases].
  final PurchaseClient? purchases;

  /// Records that this install has been through the intro. Null uses the
  /// platform default; injected by tests and the preview harness.
  final IntroStore? introStore;

  /// Whose training is on this phone, and the only way to hand it to another
  /// account. Null skips the question, which is what the preview harness, a
  /// dev persona and tests that are not about it want.
  final LocalDataGuard? localData;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Whether the session on screen was reached by creating an account.
  ///
  /// Held here because it is the only place that sees both sides of the swap:
  /// the sign-up happens in a subtree that the auth stream then replaces, so
  /// the fact would otherwise be gone by the time the shell exists.
  bool _justSignedUp = false;

  /// Set the moment the signed-in conversation finishes, so the shell arrives
  /// without waiting on the round trip that records it.
  bool _metCoachThisSession = false;

  late final IntroStore _intro = widget.introStore ?? createIntroStore();

  /// Held rather than made in `build`, because the SDK wrapper carries state a
  /// rebuild would throw away: whether `Purchases.configure` has run, and the
  /// packages a purchase needs. A fresh one per frame would reconfigure the SDK
  /// and lose the offerings between showing a price and charging for it.
  ///
  /// **Null when the build has no key**, which is a normal state rather than a
  /// failure: the coach gate then explains what a subscription buys and offers
  /// no button. A button that cannot take money fails at the moment somebody
  /// has decided to pay.
  late final PurchaseClient? _purchases =
      widget.purchases ??
      (AppConfig.current.canSell ? RevenueCatPurchases() : null);

  /// Whether this install has already been through the intro. Null while the
  /// marker is being read, which is one or two frames.
  bool? _introDone;

  /// Subscribed once, **not** rebuilt in `build`.
  ///
  /// `StreamBuilder` compares streams by identity and resubscribes when it gets
  /// a new one, and `auth.authChanges()` returns a fresh object every call — so
  /// calling it inline meant every rebuild of this widget started a new
  /// subscription, and gotrue replays `initialSession` to each new subscriber.
  /// That is one of the three reasons the restore ran more than once per launch.
  late final Stream<AuthChange> _authChanges = widget.auth.authChanges();

  /// Detaches the store whenever the session ends, however it ended.
  ///
  /// **Here, because this is the one thing that sees every sign-out.** Settings,
  /// the other-account question, a deleted account and an expired session all
  /// end the session somewhere else, and the shell is not always mounted to
  /// hear it -- the other-account question is drawn in its place. Nothing
  /// logged the store out at all before this, so a purchase made after signing
  /// out went to the account that had left.
  StreamSubscription<AuthChange>? _signOuts;

  /// What the runner told the coach to call them, when there is no account
  /// holding it. Null for anybody signed in, who has it on their profile.
  String? _localName;

  /// The account the phone's training was last checked against, and the
  /// answer: true to carry on, false to ask, null while it is being worked out.
  String? _checkedFor;
  bool? _mayUse;

  /// Whether the last frame was the shell.
  ///
  /// **A sign-in over a running shell keeps it while the check runs.** The
  /// plan gate and the Settings rows raise sign-in as a route over a shell
  /// that stays mounted, and wait on it to carry on with what the runner asked
  /// for -- swapping the shell for a blank frame would unmount it under them
  /// and drop the request. The shell holds its restore until the same answer
  /// arrives (`HomeShell._doRestoreThenLoad`), so keeping it on screen moves
  /// nothing. At launch there is no shell yet, and a blank frame beats one
  /// that paints somebody else's log first.
  bool _drewShell = false;

  /// Bumped when the phone is erased, and used as the shell's key: a shell
  /// built before the erase holds the erased runs, plan and conversation in
  /// memory, and the only honest thing to do with it is build another.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_readIntro());
    widget.localData?.erasures.addListener(_onErased);
    _signOuts = widget.auth.authChanges().listen((change) {
      if (change != AuthChange.signedOut) return;
      unawaited(_purchases?.logOut() ?? Future<void>.value());
    });
  }

  @override
  void dispose() {
    widget.localData?.erasures.removeListener(_onErased);
    unawaited(_signOuts?.cancel());
    super.dispose();
  }

  void _onErased() {
    if (!mounted) return;
    setState(() {
      _generation++;
      // The name went with everything else. Re-read rather than assumed, so
      // this and the file cannot disagree.
      _localName = null;
    });
    unawaited(_readIntro());
  }

  /// Works out whether [userId] may use what is on this phone.
  Future<void> _check(LocalDataGuard guard, String userId) async {
    final ok = await guard.mayUse(userId);
    if (!mounted || _checkedFor != userId) return;
    setState(() => _mayUse = ok);
    if (ok) return;
    // Whatever was pushed over the shell -- Settings, a sign-in form, a
    // dialog -- is still on top of it, holding the other account's name and
    // photo, and would sit over the question. Clear the way to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  Future<void> _readIntro() async {
    final done = await _intro.isDone();
    final name = await _intro.readName();
    if (!mounted) return;
    setState(() {
      _introDone = done;
      _localName = name;
    });
  }

  /// Records the intro against the install, and against the account when there
  /// is one.
  ///
  /// Both, deliberately. The local marker is what answers for a runner with no
  /// account, which is now the ordinary case; the metadata flag is what stops
  /// somebody arriving from Lift on a second device meeting the coach twice.
  /// Neither can do the other's job.
  Future<void> _introFinished(AuthRepository auth, String? name) async {
    setState(() {
      _metCoachThisSession = true;
      _introDone = true;
      _localName = name ?? _localName;
    });
    await _intro.markDone(name: name);
    if (!auth.isSignedIn) return;
    // Not allowed to fail loudly: the conversation has happened either way, and
    // a dropped connection must not strand somebody on an intro they have just
    // finished. The cost of losing it is that it is asked once more.
    try {
      await auth.markCoachMet();
      // **And the name goes to the profile too, when there is one.**
      //
      // Only somebody arriving already signed in reaches this - from Lift, or
      // on a second device - and the intro hands them their profile name to
      // correct. Without this the correction was recorded locally and the
      // profile kept the old one, so the two homes for a name disagreed from
      // the first screen, and [_name] below had to pick a winner rather than
      // just read the answer.
      //
      // A skipped question (null) leaves the profile alone rather than
      // clearing it: not answering is not the same as asking to be unnamed,
      // which is what the name row in Settings is for.
      if (name != null && name.trim().isNotEmpty) await auth.updateName(name);
    } catch (_) {}
  }

  /// What to call this runner, from whichever home has it.
  ///
  /// **The account first, the install second.** A profile name travels between
  /// devices and is the one Settings edits, so it is the answer wherever it
  /// exists; the local marker answers for the ordinary new case, where there is
  /// no account at all. `_introFinished` writes both, so the two only disagree
  /// while a profile has no name on it.
  String? _name(AuthRepository auth) => auth.currentName ?? _localName;

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final accounts =
        widget.devAccounts ??
        (kDebugMode ? AppConfig.current.devAccounts : const <DevAccount>[]);
    return StreamBuilder<AuthChange>(
      stream: _authChanges,
      builder: (context, _) {
        if (!auth.isSignedIn) {
          // Signed out, so the next sign-in -- whoever it is -- is checked
          // afresh. The guard remembers its answer, so this costs nothing when
          // it is the same account again.
          _checkedFor = null;
          _mayUse = null;
          // **An account is not the price of using this.**
          //
          // This returned the signed-out flow unconditionally, which made every
          // screen in the app - Home, recording, the log, the year - sit behind
          // an email and a password. The on-device database has been the source
          // of truth since the scaffold (CLAUDE.md rule 1) and Supabase has
          // always been a backup rather than the store, so nothing about that
          // gate was load-bearing: it was asking for an account because the
          // only door in happened to be built out of one.
          //
          // Now the intro is the door. It costs a conversation and the
          // permissions a tracker needs, both of which buy the runner
          // something, and it ends on a working app. An account is asked for at
          // the two moments it buys something too - a plan, because the coach
          // costs money to run, and backup, because that is what it is for.
          if (_introDone == null) {
            // One or two frames while the marker is read. Blank rather than a
            // spinner, for the reason `CoachFlow` gives about the disclaimer: a
            // loader that flashes before a first impression looks like a fault.
            return const Scaffold(body: SizedBox.shrink());
          }
          if (_introDone == false) {
            return _SignedOutFlow(
              auth: auth,
              devAccounts: accounts,
              onSignUpIntent: (v) => _justSignedUp = v,
              requestPermission: widget.requestPermission,
              onIntroFinished: (name) => unawaited(_introFinished(auth, name)),
            );
          }
          // Introduced, and not signed in. The tracker, on this phone only.
          _drewShell = true;
          return _shell(auth);
        }
        // **Whose training is this?** Before anything else an account does
        // here, and before the intro -- which would write this account's
        // name over the one on the phone.
        final guard = widget.localData;
        final userId = auth.currentUserId;
        if (guard != null && userId != null) {
          if (_checkedFor != userId) {
            _checkedFor = userId;
            _mayUse = null;
            unawaited(_check(guard, userId));
          }
          if (_mayUse == false) {
            _drewShell = false;
            return AnotherAccountScreen(
              whatIsHere: 'The runs, plan and coach conversations',
              email: auth.currentEmail,
              onErase: () async {
                await guard.eraseFor(userId);
                if (!mounted || _checkedFor != userId) return;
                setState(() => _mayUse = true);
              },
              onSignOut: auth.signOut,
            );
          }
          if (_mayUse == null && !_drewShell) {
            // A frame or two at launch, for the reason the intro marker's
            // blank frame gives: better than painting another account's log.
            return const Scaffold(body: SizedBox.shrink());
          }
        }
        // **Signed in is not the same as onboarded.**
        //
        // This used to read the two as one thing, because for as long as
        // signing up and onboarding were the same moment they were. They are
        // not any more. A runner who made their profile in Lift and then
        // installed this app arrives here signed in and having never met this
        // coach - and under a shared profile that is the growth path, not an
        // edge case. They would have landed in the shell, and met the location
        // dialog on top of the first run they tried to start, which is the
        // exact thing ADR-0019 asked for permissions during onboarding to
        // avoid.
        //
        // No account steps: they have a profile. Just the coach, and the
        // permissions this install has never been asked for.
        if (!_justSignedUp && !_metCoachThisSession && !auth.hasMetCoach) {
          _drewShell = false;
          return IntroScreen(
            // What the profile already knows. The name is shared across the
            // suite, so somebody arriving from Lift is not asked for it twice.
            initial: IntroAnswers(name: auth.currentName),
            requestPermission:
                widget.requestPermission ?? requestIntroPermission,
            onFinished: (name) => unawaited(_introFinished(auth, name)),
          );
        }
        _drewShell = true;
        return _shell(auth);
      },
    );
  }

  Widget _shell(AuthRepository auth) => HomeShell(
    // Constant until the phone is erased, so every other rebuild reuses the
    // shell exactly as before; see [_generation].
    key: ValueKey<int>(_generation),
    localData: widget.localData,
    justSignedUp: _justSignedUp,
    auth: auth,
    // **The wire the last change built both ends of and never joined.**
    // `IntroStore` gained a name and `HomeShell` gained the parameter to take
    // one, but nothing passed it, so `_localName` was written three times and
    // read nowhere: a runner told the coach their name in the intro and the
    // coach met them again as a stranger the moment they asked for a plan.
    runnerName: _name(auth),
    // Where the name is kept for somebody with no account, so Settings can
    // change it. Passed rather than re-created there: this store is `_intro`,
    // already open, and two stores over one marker file is a race.
    introStore: _intro,
    recorderFactory: widget.recorderFactory,
    historySource: widget.historySource,
    runEditor: widget.runEditor,
    restore: widget.restore,
    consentStore: widget.consentStore,
    eraser: widget.eraser,
    coach: widget.coach,
    planClient: widget.planClient,
    planStore: widget.planStore,
    planBackup: widget.planBackup,
    memoryStore: widget.memoryStore,
    memoryMirror: widget.memoryMirror,
    unitSettings: widget.unitSettings,
    // Read once on launch so the coach mark can say the door is locked before
    // somebody walks into it. Not the gate — the Edge Function refuses an
    // unentitled request whatever this says (ADR-0030).
    entitlements: widget.entitlements ?? SupabaseEntitlements(),
    // Presents and performs; never asked what the runner owns. The line above
    // is the one that answers that, and the Edge Function is the one that
    // enforces it.
    purchases: _purchases,
  );
}

/// Which part of the signed-out flow is on screen.
enum _Signed { welcome, intro, form }

/// The signed-out experience: the welcome screen first, then sign in / sign up.
/// Kept as local state (not a nav push) so a successful auth cleanly swaps the
/// whole subtree to [HomeShell] via [AuthGate].
class _SignedOutFlow extends StatefulWidget {
  const _SignedOutFlow({
    required this.auth,
    required this.devAccounts,
    required this.onIntroFinished,
    this.onSignUpIntent,
    this.requestPermission,
  });

  final AuthRepository auth;
  final List<DevAccount> devAccounts;

  /// Forwarded to the intro. Null keeps the real OS dialogs.
  final Future<bool> Function(IntroPermission permission)? requestPermission;

  /// Reports whether the screen below is creating an account, so the gate above
  /// can tell a brand-new runner apart from a returning one.
  final ValueChanged<bool>? onSignUpIntent;

  /// The conversation ended. The gate above records it and swaps in the shell.
  final void Function(String? name) onIntroFinished;

  @override
  State<_SignedOutFlow> createState() => _SignedOutFlowState();
}

class _SignedOutFlowState extends State<_SignedOutFlow> {
  /// Where in the signed-out flow we are.
  ///
  /// [_Signed.intro] is terminal, and no longer because it creates an account -
  /// it does not create one at all now. It ends on the last permission and the
  /// gate above swaps in the shell, signed out and entirely local.
  ///
  /// [_Signed.form] is reached only from the welcome screen, by a runner saying
  /// they already have an account: somebody signing back in wants a form their
  /// password manager recognises rather than a conversation they have had
  /// before. Creating an account is still reachable from inside that screen,
  /// and from the two places in the app that need one.
  _Signed _at = _Signed.welcome;

  /// What the intro conversation gathered, carried into the form and then into
  /// the coach's first real turn.
  IntroAnswers _answers = const IntroAnswers();

  void _open({required bool signUp}) {
    setState(() {
      _at = signUp ? _Signed.intro : _Signed.form;
      if (signUp) _answers = const IntroAnswers();
    });
    // **Deliberately does not claim a sign-up.** `signUp: true` opens the
    // *intro*, which since ADR-0019 ends on Home with nothing signed in -- so
    // announcing one here set `_justSignedUp` for any runner who merely tapped
    // "Get started", and nothing ever cleared it. `HomeShell` reads that flag
    // to decide there is nothing on the server worth restoring, so the whole
    // session then skipped both the restore and the launch backfill, whoever
    // signed in afterwards. `SignInScreen` already reports this accurately --
    // it claims a sign-up before calling `signUp` and takes the claim back when
    // no session comes of it -- and it is now the only thing that reports it.
  }

  @override
  Widget build(BuildContext context) {
    if (_at == _Signed.welcome) {
      return WelcomeScreen(
        onGetStarted: () => _open(signUp: true),
        onHaveAccount: () => _open(signUp: false),
      );
    }

    if (_at == _Signed.intro) {
      // The same guard the form has, for the same reason. Every step of this
      // flow is a *state* of one widget rather than a pushed route, so the
      // system back gesture finds nothing to pop and leaves the app — and the
      // intro is now the first screen a new runner ever answers, so without
      // this, one back swipe quits Runio from it. Adding a step to the flow
      // and not its guard is how the original bug came back wearing a new
      // screen.
      return PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          setState(() => _at = _Signed.welcome);
        },
        // **No `auth`, and that is the whole change.** `IntroScreen` already
        // ends at the last permission and calls `onFinished` when it has no
        // repository to sign up against - the path a runner arriving from Lift
        // has always taken. Every new runner takes it now.
        child: IntroScreen(
          initial: _answers,
          requestPermission: widget.requestPermission ?? requestIntroPermission,
          onBack: () => setState(() => _at = _Signed.welcome),
          onFinished: widget.onIntroFinished,
        ),
      );
    }
    // Sign-in is a *state* of this widget rather than a pushed route (see the
    // class doc), so the system back gesture had nothing to pop and went
    // straight past the app to the launcher — quitting Runio from the second
    // screen a new runner ever sees. Intercept it and step back to the welcome
    // screen, which is where the on-screen back button already goes.
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(
          () => _at = _answers.isFromIntro ? _Signed.intro : _Signed.welcome,
        );
      },
      child: SignInScreen(
        auth: widget.auth,
        initialSignUp: _answers.isFromIntro,
        // Back to the conversation rather than past it — the answers are still
        // there, and a runner who wants to change one should not have to start
        // from the welcome screen.
        onBack: () => setState(
          () => _at = _answers.isFromIntro ? _Signed.intro : _Signed.welcome,
        ),
        onSignUpIntent: widget.onSignUpIntent,
        introName: _answers.name,
        devAccounts: widget.devAccounts,
      ),
    );
  }
}
