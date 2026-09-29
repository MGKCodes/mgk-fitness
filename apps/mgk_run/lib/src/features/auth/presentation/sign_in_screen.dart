import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import 'package:mgk_ui/mgk_ui.dart';
import '../../../dev/dev_persona.dart';
import '../../../dev/dev_persona_controls.dart';
import '../data/auth_repository.dart';

/// Email + password sign in / sign up.
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

  @override
  void dispose() {
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
              () => _message = 'Check your email to confirm your account.',
            );
          }
        } else {
          // A session exists. A pushed gate dismisses itself here; the flow
          // passes nothing and is swapped out by the auth stream instead.
          widget.onAuthenticated?.call();
        }
      } else {
        await widget.auth.signIn(email: email, password: password);
        widget.onAuthenticated?.call();
      }
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
                      if (_isSignUp) ...<Widget>[
                        const SizedBox(height: 20),
                        const Entrance(index: 1, child: _WhatYouGet()),
                      ],
                      const SizedBox(height: 32),
                      // First, and only when signing up. The coach's whole
                      // pitch is that it is *yours*, and it had no idea what to
                      // call you — so the first thing it ever said was
                      // addressed to nobody. Optional on purpose: a runner who
                      // would rather not say gets a coach that simply does not
                      // use a name, which is better than a required field
                      // between them and the app.
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
                        validator: (v) => (v == null || v.length < 6)
                            ? 'At least 6 characters'
                            : null,
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _message!,
                          style: TextStyle(color: theme.colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      PrimaryButton(
                        label: _isSignUp ? 'Sign up' : 'Sign in',
                        onPressed: _submit,
                        busy: _busy,
                      ),
                      AppTextButton(
                        label: _isSignUp
                            ? 'Have an account? Sign in'
                            : 'New here? Create an account',
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _isSignUp = !_isSignUp;
                                _message = null;
                              }),
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
