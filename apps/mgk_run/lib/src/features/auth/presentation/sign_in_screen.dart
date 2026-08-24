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
        }
      } else {
        await widget.auth.signIn(email: email, password: password);
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _message = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Something went wrong. Try again.');
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
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _message = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Something went wrong. Try again.');
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
    (Icons.forum_outlined, 'A coach that answers questions about your running'),
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
