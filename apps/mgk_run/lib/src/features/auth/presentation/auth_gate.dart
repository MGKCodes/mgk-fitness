import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../coaching/data/coach_client.dart';
import '../../coaching/data/plan_client.dart';
import '../../coaching/data/coach_memory_store.dart';
import '../../history/domain/run_writer.dart';
import '../../settings/domain/backup_consent.dart';
import '../../coaching/data/plan_store.dart';
import '../../home/presentation/home_shell.dart';
import '../../settings/domain/unit_settings.dart';
import '../../onboarding/data/intro_permission_requester.dart';
import '../../onboarding/domain/intro_permission.dart';
import '../../onboarding/presentation/welcome_screen.dart';
import '../../recording/domain/run_recorder.dart';
import '../../recording/domain/run_summary.dart';
import '../data/auth_repository.dart';
import '../../onboarding/presentation/intro_screen.dart';
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
    this.coach,
    this.planClient,
    this.planStore,
    this.planBackup,
    this.memoryStore,
    this.memoryMirror,
    this.unitSettings,
    this.requestPermission,
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
  final CoachClient? coach;
  final PlanClient? planClient;
  final PlanStore? planStore;
  final PlanBackup? planBackup;

  /// Where the coach's memory lives — its transcript and rolling summary.
  final CoachMemoryStore? memoryStore;
  final CoachMemoryMirror? memoryMirror;

  /// Where the display unit is read and written.
  final UnitSettings? unitSettings;

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

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final accounts =
        widget.devAccounts ??
        (kDebugMode ? AppConfig.current.devAccounts : const <DevAccount>[]);
    return StreamBuilder<void>(
      stream: auth.authChanges(),
      builder: (context, _) {
        if (!auth.isSignedIn) {
          return _SignedOutFlow(
            auth: auth,
            devAccounts: accounts,
            onSignUpIntent: (v) => _justSignedUp = v,
            requestPermission: widget.requestPermission,
          );
        }
        return HomeShell(
          justSignedUp: _justSignedUp,
          auth: auth,
          recorderFactory: widget.recorderFactory,
          historySource: widget.historySource,
          runEditor: widget.runEditor,
          restore: widget.restore,
          consentStore: widget.consentStore,
          coach: widget.coach,
          planClient: widget.planClient,
          planStore: widget.planStore,
          planBackup: widget.planBackup,
          memoryStore: widget.memoryStore,
          memoryMirror: widget.memoryMirror,
          unitSettings: widget.unitSettings,
        );
      },
    );
  }
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

  @override
  State<_SignedOutFlow> createState() => _SignedOutFlowState();
}

class _SignedOutFlowState extends State<_SignedOutFlow> {
  /// Where in the signed-out flow we are. Creating an account goes through the
  /// coach first; signing back into one goes straight to the form, because a
  /// returning runner has met the coach already (ADR-0018).
  _Signed _at = _Signed.welcome;

  /// What the intro conversation gathered, carried into the form and then into
  /// the coach's first real turn.
  IntroAnswers _answers = const IntroAnswers();

  void _open({required bool signUp}) {
    setState(() {
      _at = signUp ? _Signed.intro : _Signed.form;
      if (signUp) _answers = const IntroAnswers();
    });
    widget.onSignUpIntent?.call(signUp);
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
        child: IntroScreen(
          initial: _answers,
          requestPermission: widget.requestPermission ?? requestIntroPermission,
          onBack: () => setState(() => _at = _Signed.welcome),
          onDone: (answers) {
            setState(() {
              _answers = answers;
              _at = _Signed.form;
            });
          },
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
