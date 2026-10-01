import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import 'package:mgk_ui/mgk_ui.dart';
import '../../../dev/dev_persona.dart';
import '../../../dev/dev_persona_controls.dart';
import '../data/auth_repository.dart';

/// Sign in or sign up: with Apple, with Google, or with an email and password.
///
/// **Apple and Google first (R10).** One tap and no password for anybody with
/// either on the phone, and the same account Lift signs into. Google is only
/// offered beside Apple (App Store guideline 4.8), and the two are drawn with
/// equal weight.
///
/// **The email form is a second step, behind "Continue with email"**, as it is
/// in Lift. With the three choices and the form on one screen, Password and the
/// button that submits it were below the bottom of a 393pt phone (board C14 and
/// K2): the screen asked for an account and hid the way to finish making one.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    this.auth = const AuthRepository(),
    this.initialSignUp = false,
    this.onBack,
    this.onSignUpIntent,
    this.onAuthenticated,
    this.introName,
    this.devAccounts = const <DevAccount>[],
  });

  final AuthRepository auth;
  final bool initialSignUp;
  final VoidCallback? onBack;

  /// Reports whether this screen is about to create an account, rather than
  /// sign back into one.
  ///
  /// **Intent, not outcome, and raised before the call rather than after it.**
  /// `signUp` publishes the auth change before it returns, so a gate that waited
  /// for the result learned about it one rebuild too late — the shell was
  /// already built, and `startOnboarding` is read once in `initState`.
  final ValueChanged<bool>? onSignUpIntent;

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

  /// The name the coach already asked for, so the form does not ask again.
  /// Null when the runner skipped it or is signing back in.
  final String? introName;

  /// Pre-seeded developer accounts for one-tap sign in. Rendered **only in
  /// debug builds** (see [build]); empty in release and in normal use.
  final List<DevAccount> devAccounts;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.introName ?? '',
  );
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late bool _isSignUp = widget.initialSignUp;
  bool _busy = false;
  String? _message;

  /// The next step rather than a failure: a confirmation to go and look for,
  /// a reset on its way. Said in the quiet colour, because in the error colour
  /// "Check your email to confirm your account" read as the account not being
  /// made.
  String? _notice;

  bool _sendingReset = false;

  /// Whether the email form is showing, rather than the three ways in.
  bool _withEmail = false;

  void _showEmail(bool show) => setState(() {
    _withEmail = show;
    _message = null;
    _notice = null;
  });

  /// Which provider's sheet is up, if any.
  SignInProvider? _asking;

  /// Apple on Android: signing in continues in the browser, and the session
  /// arrives on the auth stream afterwards. A pushed gate needs telling when it
  /// does; the flow is swapped out by the same stream on its own.
  StreamSubscription<AuthChange>? _arrivals;

  Future<void> _withProvider(SignInProvider provider) async {
    if (_busy || _asking != null) return;
    // Intent, not outcome, and before the call — see [SignInScreen
    // .onSignUpIntent]. Apple and Google do both without saying which, so the
    // half of the screen the runner chose is the only answer there is.
    widget.onSignUpIntent?.call(_isSignUp);
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
          // No session, so the claim above is taken back rather than left to
          // fire on a later sign-in.
          widget.onSignUpIntent?.call(false);
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
      widget.onSignUpIntent?.call(false);
      if (mounted) setState(() => _message = _messageFor(error));
    } finally {
      if (mounted) setState(() => _asking = null);
    }
  }

  @override
  void dispose() {
    unawaited(_arrivals?.cancel());
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
      _notice = null;
    });
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    try {
      if (_isSignUp) {
        widget.onSignUpIntent?.call(true);
        final signedIn = await widget.auth.signUp(
          email: email,
          password: password,
          name: _nameController.text,
        );
        if (!signedIn) {
          // No session, so no shell will be built from this — take the claim
          // back rather than leave it to fire on a later sign-in.
          widget.onSignUpIntent?.call(false);
          if (mounted) {
            setState(
              () => _notice = 'Check your email to confirm your account.',
            );
          }
        } else {
          // A session exists. A pushed gate dismisses itself here; the flow
          // passes nothing and is swapped out by the auth stream instead.
          widget.onAuthenticated?.call();
        }
      } else {
        // Signing *in*, whatever was claimed earlier on this screen. Apple on
        // Android leaves the claim standing while its browser is open, and
        // somebody who gives up on that and signs in with their email instead
        // must not arrive as a new runner.
        widget.onSignUpIntent?.call(false);
        await widget.auth.signIn(email: email, password: password);
        widget.onAuthenticated?.call();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          // Signing in before following the link is the next step, not a
          // failure, and with confirmation on it is what a new runner does
          // first. The server's own words are "Email not confirmed", in the
          // error colour, which read as the account not having been made.
          if (_awaitingConfirmation(error)) {
            _notice = 'Check your email and follow the link, then sign in.';
          } else {
            _message = _messageFor(error);
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _notice = null;
        _message = 'Enter your email first.';
      });
      return;
    }
    setState(() => _sendingReset = true);
    await widget.auth.sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _sendingReset = false;
      _message = null;
      // The same words whether or not the address has an account: anything
      // else is a way for anybody to find out who is registered.
      _notice = 'If that address has an account, a reset link is on its way.';
    });
  }

  /// One-tap sign in as a pre-seeded developer account (debug builds only).
  Future<void> _quickSignIn(DevAccount account) async {
    // Signing *in*, whatever the screen was showing. Without this the sign-up
    // intent set by "Get started" survived, so every dev and persona entry
    // arrived at Home with `startOnboarding` still true and got the coach flow
    // pushed over an account that has been onboarded for weeks.
    widget.onSignUpIntent?.call(false);
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
    return Scaffold(
      appBar: widget.onBack == null
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              leading: BackButton(onPressed: widget.onBack),
            ),
      // The same photograph the welcome screen sits on. Without it the brand
      // evaporated at the first tap: a full-bleed monochrome entry point handed
      // straight over to a bare form on a flat background, which read as a
      // different app.
      extendBodyBehindAppBar: true,
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/onboarding.jpg',
        opacity: 0.34,
        scrim: ScrimStrength.grounded,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // **Never the app's name.** What is being made here
                      // is not an account for this app - it is the profile
                      // that works across every app in the suite, and heading
                      // the screen with one app's name says the opposite of
                      // that to the person who already has one from Lift.
                      Text(
                        '$kPlatformName Profile',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      // The words arrive; the form does not.
                      //
                      // This is the first screen anybody sees and it appeared
                      // in a single frame. Only the parts nobody types into are
                      // choreographed: staggering the fields themselves would
                      // put movement under a cursor and risk fighting autofill
                      // and focus for the sake of a flourish on the one screen
                      // that should feel most solid.
                      Entrance(
                        child: Text(
                          _isSignUp ? 'Create your account' : 'Welcome back',
                          style: theme.textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Said on both halves of the screen, not just sign-up.
                      // Someone signing in may be arriving from Lift with a
                      // profile they did not know reached this far, and that
                      // is worth telling them at the moment they are wondering
                      // whether their details will work.
                      Entrance(
                        child: Text(
                          'One profile for every $kPlatformName app. The same '
                          'sign-in works in Lift and in anything else we make, '
                          'so you only set this up once.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // Signing up and signing in are not the same act, and the
                      // screen used to tell them apart by one word. Someone
                      // signing in already knows what they are buying; someone
                      // signing up is deciding, and had two fields and a button
                      // to decide from.
                      //
                      // On the choice, not on the form: by the time somebody is
                      // typing an address they have decided.
                      if (_isSignUp && !_withEmail) ...<Widget>[
                        const SizedBox(height: 20),
                        const Entrance(index: 1, child: _WhatYouGet()),
                      ],
                      const SizedBox(height: 32),
                      if (!_withEmail) ...<Widget>[
                        ProviderSignInButton.apple(
                          busy: _asking == SignInProvider.apple,
                          onPressed: _busy || _asking != null
                              ? null
                              : () => _withProvider(SignInProvider.apple),
                        ),
                        const SizedBox(height: 12),
                        ProviderSignInButton.google(
                          busy: _asking == SignInProvider.google,
                          onPressed: _busy || _asking != null
                              ? null
                              : () => _withProvider(SignInProvider.google),
                        ),
                        const SizedBox(height: 12),
                        AppOutlinedButton(
                          label: 'Continue with email',
                          icon: Icons.mail_outline,
                          expand: true,
                          onPressed: _busy || _asking != null
                              ? null
                              : () => _showEmail(true),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          // O2. Apple's relay address is a different address,
                          // so there is nothing to join it to an existing
                          // account by.
                          'Choosing Hide My Email with Apple starts a separate '
                          'account.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ] else ...<Widget>[
                        // First, and only when signing up. The coach's whole
                        // pitch is that it is *yours*, and it had no idea what
                        // to call you — so the first thing it ever said was
                        // addressed to nobody. Optional on purpose: a runner
                        // who would rather not say gets a coach that simply
                        // does not use a name, which is better than a required
                        // field between them and the app.
                        // Only when the coach has not already asked. Asking a
                        // second time would undo the point of asking in the
                        // conversation at all.
                        if (_isSignUp && widget.introName == null) ...<Widget>[
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.givenName],
                            decoration: const InputDecoration(
                              labelText: 'First name (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || !v.contains('@'))
                              ? 'Enter a valid email'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                          ),
                          // Eight, as Lift asks and the reset page does: it
                          // is one account. Only when making one. Refusing a
                          // short password at sign-in would lock out anybody
                          // who chose one while Run still asked for six.
                          validator: (v) {
                            final String value = v ?? '';
                            if (value.isEmpty) return 'Enter your password.';
                            if (_isSignUp && value.length < 8) {
                              return 'Use at least 8 characters.';
                            }
                            return null;
                          },
                        ),
                      ],
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
                      if (_withEmail) ...<Widget>[
                        const SizedBox(height: 24),
                        PrimaryButton(
                          label: _isSignUp ? 'Sign up' : 'Sign in',
                          onPressed: _submit,
                          busy: _busy,
                        ),
                        // Signing in only: somebody making an account has no
                        // password to forget. The link opens a page on the
                        // site, not the app, so it works from a laptop's inbox
                        // too.
                        if (!_isSignUp)
                          AppTextButton(
                            label: 'Forgot your password?',
                            onPressed: _busy || _sendingReset
                                ? null
                                : _resetPassword,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                            ),
                          ),
                      ] else
                        const SizedBox(height: 8),
                      AppTextButton(
                        label: _isSignUp
                            ? 'Have an account? Sign in'
                            : 'New here? Create an account',
                        onPressed: _busy || _asking != null
                            ? null
                            : () => setState(() {
                                _isSignUp = !_isSignUp;
                                _message = null;
                                _notice = null;
                              }),
                      ),
                      if (_withEmail)
                        AppTextButton(
                          label: 'Other ways to sign in',
                          onPressed: _busy ? null : () => _showEmail(false),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                          ),
                        ),
                      if (kDebugMode &&
                          widget.devAccounts.isNotEmpty) ...<Widget>[
                        _DevSignIn(
                          accounts: widget.devAccounts,
                          busy: _busy,
                          onSelected: (account) {
                            // Signing in plainly means the real account: drop a
                            // persona left on from an earlier session, or the
                            // runner's own data would silently stay hidden.
                            setDevPersona(null);
                            unawaited(_quickSignIn(account));
                          },
                        ),
                        // The same sign-in, entered as a seeded runner. Uses the
                        // first configured account because the persona decides
                        // what is on screen — the account only gets us past auth.
                        DevPersonaButtons(
                          busy: _busy,
                          onSelected: (persona) {
                            setDevPersona(persona);
                            unawaited(_quickSignIn(widget.devAccounts.first));
                          },
                        ),
                      ],
                    ],
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

/// Whether the server refused a sign-in because the address is unconfirmed.
///
/// Matched on the message as Lift does: gotrue's code for it has changed
/// between versions, and the words have not.
bool _awaitingConfirmation(Object error) =>
    error is AuthException &&
    error.message.toLowerCase().contains('not confirmed');

/// What to print when authenticating fails.
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
/// prints the server's own words — right for a wrong password, and the reason
/// it is kept — was one line away from showing `ClientException with
/// SocketException: Failed host lookup ...` to somebody who had simply left the
/// radio off.
///
/// Those two types are the whole reachable set, which is worth saying because
/// the instinct here is to reach for `dart:io`. A raw `SocketException` or
/// `ClientException` cannot arrive: gotrue wraps its own, and the
/// `core.profiles` write that goes out through postgrest is now best-effort
/// inside [AuthRepository.ensureProfileBestEffort], so it throws nothing at
/// this screen. [TimeoutException] is what [AuthRepository.timeout] raises when
/// a call blows its deadline. Importing `dart:io` for a case that cannot happen
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
  // A real answer from the server — wrong password, weak password, an address
  // already registered — said in its own words rather than a paraphrase.
  if (error is AuthException) return error.message;
  return 'Something went wrong. Try again.';
}

/// What signing up is actually for, on the screen where someone is deciding.
///
/// Three facts rather than three adjectives. The welcome screen makes the
/// promise ("Every run, coached"); this is the part that says what arrives
/// after the password, which is the question a stranger is actually holding
/// when they look at an empty email field.
///
/// **These describe the free account and nothing else** (ADR-0019). The first
/// line used to promise "a plan built round the days you can run", which is now
/// the paid thing behind the plan gate — so the one screen where somebody is
/// deciding whether to sign up was promising the one thing signing up does not
/// give them. A plan is sold at the gate, by the coach, where the price is also
/// said. It is not sold here.
class _WhatYouGet extends StatelessWidget {
  const _WhatYouGet();

  static const List<(IconData, String)> _lines = <(IconData, String)>[
    (Icons.play_circle_outline, 'Every run tracked, and every run kept'),
    // The coach is the paid half (ADR-0030): what an account gives is the
    // way to subscribe to it, not the coach.
    (
      Icons.forum_outlined,
      'With a subscription, a coach that answers questions about your running',
    ),
    (Icons.phone_iphone, 'Your runs on your phone, backed up only if you say'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final (icon, text) in _lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
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
