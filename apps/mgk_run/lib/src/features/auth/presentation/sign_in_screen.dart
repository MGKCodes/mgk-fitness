import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/brand.dart';
import '../../../core/config/app_config.dart';
import 'package:mgk_ui/mgk_ui.dart';
import '../../../dev/dev_persona.dart';
import '../../../dev/dev_persona_controls.dart';
import '../../legal/domain/legal_urls.dart';
import '../../legal/presentation/privacy_policy_screen.dart';
import '../data/auth_repository.dart';

/// Sign in or sign up: with Apple, with Google, or with an email address.
///
/// **Apple and Google first (R10).** One tap and no password for anybody with
/// either on the phone, and the same account Lift signs into. Google is only
/// offered beside Apple (App Store guideline 4.8), and the two are drawn with
/// equal weight.
///
/// **Laid out as Lift's sign-in is (1.0.1).** The photograph above, at full
/// strength, and everything to read and press below it, on the dark the
/// photograph fades into: which app this is and whose account, the three ways
/// in, and the terms and privacy line at the foot. It was the welcome's
/// photograph dimmed to a third under content centred on the screen, which
/// read as a different screen from Lift's for the same account.
///
/// **The email path is a second step, behind "Continue with email"**, as it is
/// in Lift. With the three choices and a form on one screen, Password and the
/// button that submits it were below the bottom of a 393pt phone (board C14 and
/// K2): the screen asked for an account and hid the way to finish making one.
///
/// **The address first (ADR-0047, 1.0.2).** The email path asks for the
/// address alone and looks it up, and the step after it is the one that
/// address needs: *Welcome back* and its password, *This address signs in with
/// Apple* (or Google), or *Create your account* and then a 6-digit code from
/// the email. It replaces a form with two modes and a switch between them,
/// which made people decide whether they were signing in or signing up before
/// they had typed anything, and which this screen then reported upwards as a
/// guess about whether the account was new. Nothing is guessed now: `AuthGate`
/// reads that from the account.
///
/// **The steps are the suite's, not this screen's.** Which step comes next and
/// what each failure is called live in `mgk_auth`'s [EmailSignInFlow], and
/// `mgk_ui`'s [EmailSignInSteps] draws them, so Lift's sign-in says the same
/// thing in the same words. What this screen decides is everything around
/// them: the head, the providers, the debug sign-in, and what happens once
/// somebody is signed in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    this.auth = const AuthRepository(),
    this.onBack,
    this.onAuthenticated,
    this.devAccounts = const <DevAccount>[],
    this.clock,
  });

  final AuthRepository auth;
  final VoidCallback? onBack;

  /// There is now a session. **Only a screen that was *pushed* needs this.**
  ///
  /// In the signed-out flow this screen is a state of `AuthGate`, and a
  /// successful sign-in swaps the whole subtree for the shell — nothing has to
  /// be dismissed, because the screen ceases to exist. A gate raised from
  /// inside the running app is the opposite case: it is a route over a shell
  /// that stays exactly where it is, so without this the runner signs up
  /// successfully and is left sitting on the form they have just finished, with
  /// the thing they asked for waiting behind a back gesture nobody told them to
  /// make.
  ///
  /// Null keeps the flow behaviour, which needs no dismissal.
  final VoidCallback? onAuthenticated;

  /// Pre-seeded developer accounts for one-tap sign in. Rendered **only in
  /// debug builds** (see [build]); empty in release and in normal use.
  final List<DevAccount> devAccounts;

  /// Now, for the wait before another code can be sent. Null is the real time.
  /// A board draws a fixed moment with it, so its countdown reads the same
  /// every time the plate is drawn.
  final DateTime Function()? clock;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  /// The email path: its step, the address, what it is saying and whether a
  /// request is running. Owned here and drawn by [EmailSignInSteps].
  late final EmailSignInFlow _flow = EmailSignInFlow(
    api: widget.auth.emailSignIn(),
    clock: widget.clock,
  )..addListener(_flowChanged);

  void _flowChanged() {
    if (mounted) setState(() {});
  }

  /// The debug quick sign-in is running.
  bool _busy = false;

  /// What went wrong with Apple, Google or the debug sign-in. The email path
  /// says its own failures through [_flow].
  String? _message;

  /// The next step rather than a failure: Apple's browser on Android, which
  /// finishes the sign-in elsewhere. Said in the quiet colour.
  String? _notice;

  /// Whether the email path is showing, rather than the three ways in.
  bool _withEmail = false;

  void _showEmail(bool show) {
    _flow.clearMessages();
    setState(() {
      _withEmail = show;
      _message = null;
      _notice = null;
    });
  }

  /// Which provider's sheet is up, if any.
  SignInProvider? _asking;

  /// Apple on Android: signing in continues in the browser, and the session
  /// arrives on the auth stream afterwards. A pushed gate needs telling when it
  /// does; the flow is swapped out by the same stream on its own.
  StreamSubscription<AuthChange>? _arrivals;

  /// Whether anything on the screen is running, so nothing else starts.
  bool get _working => _busy || _asking != null || _flow.busy;

  /// Signs in with Apple or Google: from the three choices, and from the email
  /// path's *This address signs in with Apple* (or Google).
  ///
  /// **Says nothing about whether the account is new.** It used to report the
  /// screen's guess before the call, because Apple and Google make an account
  /// or sign into one without saying which. The account says which now
  /// (`AuthRepository.accountIsNew`), and `AuthGate` asks it.
  Future<void> _withProvider(SignInProvider provider) async {
    if (_working) return;
    _flow.clearMessages();
    setState(() {
      _asking = provider;
      _message = null;
      _notice = null;
    });
    try {
      final outcome = switch (provider) {
        SignInProvider.apple => await widget.auth.signInWithApple(),
        SignInProvider.google => await widget.auth.signInWithGoogle(),
      };
      switch (outcome) {
        case ProviderOutcome.signedIn:
          widget.onAuthenticated?.call();
        case ProviderOutcome.cancelled:
          // They closed the sheet. Nothing went wrong, so nothing is said.
          break;
        case ProviderOutcome.continuing:
          await _arrivals?.cancel();
          _arrivals = widget.auth.authChanges().listen((change) {
            if (change == AuthChange.signedIn) widget.onAuthenticated?.call();
          });
          if (mounted) {
            setState(
              () => _notice = 'Finish signing in with Apple in your browser.',
            );
          }
      }
    } catch (error) {
      if (mounted) setState(() => _message = _messageFor(error));
    } finally {
      if (mounted) setState(() => _asking = null);
    }
  }

  /// Finishes the email path once a step has signed somebody in: signing in
  /// with a password, the code that confirms a new address, or (with
  /// confirmation off) making the account.
  ///
  /// The profile row first, as every other sign-in writes it, and never in
  /// the way: a row that does not land is the next launch's to write (see
  /// `AuthRepository.ensureProfileBestEffort`), not a reason to say an account
  /// that exists has failed. Then the gate that raised this screen, if one
  /// did.
  Future<void> _finish(Future<bool> step) async {
    if (!await step) return;
    await widget.auth.ensureProfileBestEffort();
    widget.onAuthenticated?.call();
  }

  /// The password rule as the checklist under *Choose a password*, part by
  /// part, in the order [PasswordCheck] states it.
  static List<PasswordRequirement> _requirements(String password) {
    final check = PasswordCheck.of(password);
    return <PasswordRequirement>[
      PasswordRequirement('8 characters', met: check.longEnough),
      PasswordRequirement('a number', met: check.hasNumber),
      PasswordRequirement('a symbol', met: check.hasSymbol),
    ];
  }

  /// The flow's step as the steps widget draws it: the same five, one decided
  /// in `mgk_auth` and one drawn in `mgk_ui`, so neither package needs the
  /// other.
  static EmailStage _stageOf(EmailStep step) => switch (step) {
    EmailStep.address => EmailStage.address,
    EmailStep.password => EmailStage.password,
    EmailStep.provider => EmailStage.provider,
    EmailStep.create => EmailStage.create,
    EmailStep.code => EmailStage.code,
  };

  @override
  void dispose() {
    unawaited(_arrivals?.cancel());
    _flow.removeListener(_flowChanged);
    // A request still running reports back to the flow when it ends, and a
    // disposed notifier throws when told. Left to the collector instead: it
    // holds nothing once nobody listens.
    if (!_flow.busy) _flow.dispose();
    super.dispose();
  }

  /// One-tap sign in as a pre-seeded developer account (debug builds only).
  Future<void> _quickSignIn(DevAccount account) async {
    setState(() {
      _busy = true;
      _message = null;
      _notice = null;
    });
    try {
      await widget.auth.signIn(
        email: account.email,
        password: account.password,
      );
      widget.onAuthenticated?.call();
    } catch (error) {
      if (mounted) {
        setState(() => _message = _messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = _stageOf(_flow.step);
    return Scaffold(
      appBar: widget.onBack == null
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              leading: BackButton(onPressed: widget.onBack),
            ),
      // A photograph at full strength above, fading to the base where the
      // choices are, the way Lift's sign-in draws its own. The night road,
      // which the summary uses too: dark and backlit, as Lift's is. The
      // welcome's foggy path was tried first and came out a flat grey. Its
      // runner sits behind the heading; a photograph made for this screen, as
      // Lift's was, would put the runner above it.
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.bg,
      body: PhotoBackdrop.hero(
        image: 'assets/images/backgrounds/summary.jpg',
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              // Anchored to the bottom, as Lift's is: with the keyboard up, the
              // field being typed in and its button stay in view and the head
              // is what scrolls away.
              reverse: true,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxl + AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      constraints.maxHeight -
                      AppSpacing.xxl -
                      AppSpacing.xl -
                      AppSpacing.lg,
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Which app this is, then whose account: the suite's
                        // head, shared with Lift. The account is one account,
                        // so both apps say so in the same words, each under its
                        // own icon.
                        // On the choices and the address it says both, as
                        // Lift's does: nothing yet says which this is. Once
                        // the address has been looked up, the step says.
                        ProfileHeader(
                          line: _withEmail
                              ? stage.headline
                              : 'Sign in or create your account',
                          otherApp: 'Lift',
                          app: const AppIdentity(
                            icon: AssetImage(
                              'assets/images/brand/app_icon.png',
                            ),
                            name: kAppName,
                          ),
                        ),
                        // No list of what an account gives, as Lift's has none:
                        // the head says what the account is, and the welcome
                        // has already made the promise.
                        const SizedBox(height: AppSpacing.xl),
                        if (!_withEmail) ...<Widget>[
                          ProviderSignInButton.apple(
                            busy: _asking == SignInProvider.apple,
                            onPressed: _working
                                ? null
                                : () => _withProvider(SignInProvider.apple),
                          ),
                          const SizedBox(height: 12),
                          ProviderSignInButton.google(
                            busy: _asking == SignInProvider.google,
                            onPressed: _working
                                ? null
                                : () => _withProvider(SignInProvider.google),
                          ),
                          const SizedBox(height: 12),
                          AppOutlinedButton(
                            label: 'Continue with email',
                            icon: Icons.mail_outline,
                            expand: true,
                            onPressed: _working ? null : () => _showEmail(true),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            // O2. Apple's relay address is a different address,
                            // so there is nothing to join it to an existing
                            // account by, and the lookup cannot see it coming.
                            'Choosing Hide My Email with Apple starts a separate '
                            'account.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_message != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _message!,
                              style: TextStyle(color: theme.colorScheme.error),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          if (_notice != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _notice!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ] else
                          EmailSignInSteps(
                            stage: stage,
                            email: _flow.email,
                            provider: _flow.status == AccountStatus.google
                                ? SignInProvider.google
                                : SignInProvider.apple,
                            busy: _flow.busy || _busy,
                            providerBusy: _asking != null,
                            // The provider's and the debug sign-in's failures
                            // are said where the step says its own.
                            error: _flow.error ?? _message,
                            notice: _flow.notice ?? _notice,
                            resendAt: _flow.resendAt,
                            clock: widget.clock ?? DateTime.now,
                            suggest: _flow.suggestionFor,
                            requirements: _requirements,
                            onAddress: (typed) =>
                                unawaited(_flow.submitAddress(typed)),
                            onPassword: (password) =>
                                unawaited(_finish(_flow.signIn(password))),
                            onForgotPassword: () =>
                                unawaited(_flow.forgotPassword()),
                            onProvider: () => unawaited(
                              _withProvider(
                                _flow.status == AccountStatus.google
                                    ? SignInProvider.google
                                    : SignInProvider.apple,
                              ),
                            ),
                            onSetPassword: () =>
                                unawaited(_flow.setPasswordInstead()),
                            onCreate: (password) => unawaited(
                              _finish(_flow.createAccount(password)),
                            ),
                            onCode: (code) =>
                                unawaited(_finish(_flow.confirm(code))),
                            onResend: () => unawaited(_flow.resend()),
                            onChangeAddress: _flow.changeAddress,
                            onOtherWays: () => _showEmail(false),
                          ),
                        if (kDebugMode &&
                            widget.devAccounts.isNotEmpty) ...<Widget>[
                          _DevSignIn(
                            accounts: widget.devAccounts,
                            busy: _working,
                            onSelected: (account) {
                              // Signing in plainly means the real account: drop
                              // a persona left on from an earlier session, or
                              // the runner's own data would silently stay
                              // hidden.
                              setDevPersona(null);
                              unawaited(_quickSignIn(account));
                            },
                          ),
                          // The same sign-in, entered as a seeded runner. Uses
                          // the first configured account because the persona
                          // decides what is on screen — the account only gets
                          // us past auth.
                          DevPersonaButtons(
                            busy: _working,
                            onSelected: (persona) {
                              setDevPersona(persona);
                              unawaited(_quickSignIn(widget.devAccounts.first));
                            },
                          ),
                        ],
                        // Required wherever an account can be made, and shown
                        // on every step, as Lift shows it: somebody signing in
                        // on a new phone is accepting the same terms.
                        const SizedBox(height: AppSpacing.xl),
                        const _LegalLinks(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What to print when Apple, Google or the debug sign-in fails. The email path
/// has its own words, the suite's, in `EmailSignInFlow`.
///
/// **A dead connection earns its own sentence.** This screen used to print
/// `AuthException.message` and collapse everything else into "Something went
/// wrong. Try again." — which describes a broken app, names nothing the runner
/// can go and put right, and invites the one retry guaranteed to fail again.
/// Build 12 was field-tested with aeroplane mode left on and that is the
/// sentence it produced, after a spinner that had already run for as long as
/// the runner was willing to wait.
///
/// [AuthRetryableFetchException] is tested **before its own supertype**, and
/// that ordering is why this function exists at all. gotrue does not let a
/// socket error out raw: it wraps every failed fetch in an `AuthException`
/// whose `message` is the underlying error's `toString()`. So the branch that
/// prints the server's own words was one line away from showing
/// `ClientException with SocketException: Failed host lookup ...` to somebody
/// who had simply left the radio off.
///
/// Those two types are the whole reachable set, which is worth saying because
/// the instinct here is to reach for `dart:io`. A raw `SocketException` or
/// `ClientException` cannot arrive: gotrue wraps its own, and the
/// `core.profiles` write that goes out through postgrest is best-effort inside
/// [AuthRepository.ensureProfileBestEffort], so it throws nothing at this
/// screen. [TimeoutException] is what [AuthRepository.timeout] raises when a
/// call blows its deadline. Importing `dart:io` for a case that cannot happen
/// would drag this screen out of the web preview harness's import graph for
/// nothing.
///
/// The words are the ones the account-deletion path already uses for the same
/// fact, because it is the same fact.
String _messageFor(Object error) {
  if (error is ProviderSignInException) {
    return switch (error.failure) {
      ProviderFailure.unavailable =>
        'We could not reach the server. Check your connection and try again.',
      ProviderFailure.refused =>
        'That sign-in did not go through. Try again, or use your email.',
    };
  }
  if (error is AuthRetryableFetchException || error is TimeoutException) {
    return 'We could not reach the server. Check your connection and try '
        'again.';
  }
  // A real answer from the server to the debug sign-in, said in its own words
  // rather than a paraphrase.
  if (error is AuthException) return error.message;
  return 'Something went wrong. Try again.';
}

/// The terms and privacy links at the foot of the sign-in, as Lift's sign-in
/// has them.
///
/// One sentence with two tappable halves rather than two more buttons under
/// the choices. Apple wants the documents reachable where an account is made,
/// and a person wants to know what they are agreeing to. The privacy policy
/// opens in the app; the terms open on the site, as Privacy & legal opens them.
class _LegalLinks extends StatefulWidget {
  const _LegalLinks();

  @override
  State<_LegalLinks> createState() => _LegalLinksState();
}

class _LegalLinksState extends State<_LegalLinks> {
  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = _openTerms;
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen()),
    );

  Future<void> _openTerms() async {
    final Uri uri = Uri.parse(kTermsOfUseUrl);
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (!mounted) return;
    // Says where they are when the browser will not open.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open the terms. They are at $uri')),
    );
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: 1.4,
    );
    final link = base?.copyWith(
      color: AppColors.textSecondary,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.textTertiary,
    );
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          const TextSpan(text: 'By continuing you agree to the '),
          TextSpan(text: 'terms of use', style: link, recognizer: _terms),
          const TextSpan(text: ' and the '),
          TextSpan(text: 'privacy policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: base,
    );
  }
}

/// Debug-only quick sign-in: a labelled row of one-tap buttons for the
/// pre-seeded [DevAccount]s. Never built in release (its only call site is
/// guarded by [kDebugMode]).
class _DevSignIn extends StatelessWidget {
  const _DevSignIn({
    required this.accounts,
    required this.busy,
    required this.onSelected,
  });

  final List<DevAccount> accounts;
  final bool busy;
  final ValueChanged<DevAccount> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Developer sign-in',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final account in accounts)
              OutlinedButton(
                onPressed: busy ? null : () => onSelected(account),
                child: Text(account.label),
              ),
          ],
        ),
      ],
    );
  }
}
