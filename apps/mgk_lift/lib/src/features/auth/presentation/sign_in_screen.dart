import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../legal/domain/legal_copy.dart';
import '../../legal/domain/legal_document.dart';
import '../../legal/presentation/legal_document_screen.dart';
import '../domain/account.dart';

/// Sign in, or make an account: with Apple, with Google, or with an email.
///
/// **Apple and Google first, email one tap behind them (R10).** Most people
/// arriving here already have one of the two on the phone, and for them it is
/// one tap and no password; the design review found the email form was the
/// whole screen, with nothing to say that anything else was possible. Google
/// is only offered beside Apple (App Store guideline 4.8), and the two are
/// drawn with equal weight.
///
/// **Set on a photograph (R1).** This is one of the two screens that lead with
/// one; the headline and the choices sit low, over the dark floor the image
/// was composed with.
///
/// **One screen for signing in and for making an account.** Apple and Google
/// do both without being told which; the email form toggles, as it always has,
/// because its fields are identical and two screens would mean a "wrong
/// screen" dead end for anybody who tapped the wrong entry point.
///
/// This is never in anybody's way. Tracking works signed out, and the screen
/// says so at the bottom — somebody who opened it by accident should be able to
/// leave without feeling they have lost something.
///
/// Pops with true once somebody is signed in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.auth,
    this.pendingWorkouts = 0,
    this.emailFirst = false,
  });

  final AuthService auth;

  /// How many sessions exist only on this phone. Shown as the reason to bother,
  /// because it is the true one and it is specific.
  final int pendingWorkouts;

  /// Opens on the email form rather than the three choices.
  final bool emailFirst;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

enum _Provider { apple, google }

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  late bool _withEmail = widget.emailFirst;
  bool _creating = false;
  bool _busy = false;
  _Provider? _asking;
  bool _obscure = true;
  String? _error;
  String? _notice;

  /// Watches for an account arriving from outside this screen: Apple's sign-in
  /// on Android finishes in the browser and comes back through a link.
  StreamSubscription<Account?>? _arrivals;

  /// Popped already. Two things can finish a sign-in — the call that made it
  /// and the stream that reports it — and only one of them may close the
  /// screen, or the second would close whatever was under it.
  bool _done = false;

  bool get _anyBusy => _busy || _asking != null;

  @override
  void initState() {
    super.initState();
    _arrivals = widget.auth.changes.listen((account) {
      if (account != null) _finish();
    });
  }

  @override
  void dispose() {
    unawaited(_arrivals?.cancel());
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(true);
  }

  Future<void> _withProvider(_Provider provider) async {
    if (_anyBusy) return;
    setState(() {
      _asking = provider;
      _error = null;
      _notice = null;
    });
    try {
      final outcome = switch (provider) {
        _Provider.apple => await widget.auth.signInWithApple(),
        _Provider.google => await widget.auth.signInWithGoogle(),
      };
      if (!mounted) return;
      switch (outcome) {
        case ProviderOutcome.signedIn:
          _finish();
        case ProviderOutcome.cancelled:
          // Closing Apple's or Google's sheet is a choice, not a failure, and
          // a message would read as one.
          setState(() => _asking = null);
        case ProviderOutcome.continuing:
          setState(() {
            _asking = null;
            _notice = 'Finish signing in with Apple in your browser.';
          });
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _asking = null;
        _error = e.failure.message;
      });
    }
  }

  Future<void> _submit() async {
    if (_anyBusy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      if (_creating) {
        await widget.auth.signUp(email: _email.text, password: _password.text);
      } else {
        await widget.auth.signIn(email: _email.text, password: _password.text);
      }
      _finish();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Confirmation is not a failure, it is the next step, and colouring it
        // like an error would read as "your account was not created".
        if (e.failure == AuthFailure.needsConfirmation) {
          _notice = e.failure.message;
        } else {
          _error = e.failure.message;
        }
      });
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email first.');
      return;
    }
    await widget.auth.sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _error = null;
      // Says the same thing whether or not the address has an account. The
      // alternative is a way for anybody to find out who is registered here.
      _notice = 'If that address has an account, a reset link is on its way.';
    });
  }

  void _showEmail(bool show) => setState(() {
    _withEmail = show;
    _error = null;
    _notice = null;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;

    // Backing out mid-request would leave the lifter on Track not knowing
    // whether they are signed in — the request completes either way, and the
    // stream that reports it fires into a disposed screen. Two seconds of a
    // disabled arrow is the cheaper confusion.
    return PopScope(
      canPop: !_anyBusy,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: PhotoBackdrop.hero(
          image: 'assets/images/backgrounds/hero_sign_in.webp',
          child: Stack(
            children: <Widget>[
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    // Anchored to the bottom, so with the keyboard up the
                    // field being typed in and its button stay in view and
                    // the headline is what scrolls away.
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            _headline,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                            ),
                          ),
                          if (_support() case final String line) ...<Widget>[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              line,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          AnimatedSize(
                            duration: AppMotion.base,
                            curve: AppMotion.standard,
                            alignment: Alignment.bottomCenter,
                            child: _withEmail
                                ? _emailForm(theme)
                                : _choices(theme),
                          ),
                          if (_error != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              _error!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.danger,
                              ),
                            ),
                          ],
                          if (_notice != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              _notice!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            // The escape hatch. Somebody who opened this by
                            // accident should be able to leave without feeling
                            // they have lost something, because they have not.
                            'You do not need an account to track your '
                            'training.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                              height: 1.4,
                            ),
                          ),
                          // Required wherever an account can be created, and
                          // this screen is the only place it can be. Shown on
                          // every step: somebody signing in on a new phone is
                          // re-accepting the same terms, and a link that
                          // appears and disappears reads as a trick.
                          const SizedBox(height: AppSpacing.sm),
                          const _LegalLinks(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: top + AppSpacing.xs,
                left: AppSpacing.sm,
                child: AppIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onPressed: _anyBusy
                      ? null
                      : () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _headline {
    if (!_withEmail) return 'Sign in';
    return _creating ? 'Create an account' : 'Welcome back';
  }

  /// What is worth saying under the headline, or null when nothing is.
  ///
  /// On the choices: that the same buttons make an account, because "Sign in"
  /// alone reads as a door for people who already have one.
  ///
  /// Then one fact, and only when there is one — sessions that exist in a
  /// single place. That is state the person may not have, not an argument for
  /// the account. Signing in with an email gets nothing more: somebody with an
  /// account knows what it does.
  String? _support() {
    final n = widget.pendingWorkouts;
    final pending = n == 0
        ? null
        : '$n session${n == 1 ? '' : 's'} ${n == 1 ? 'is' : 'are'} on this '
              'phone only.';
    if (!_withEmail) {
      const both = 'New to Lift? These make your account too.';
      return pending == null ? both : '$both $pending';
    }
    return _creating ? pending : null;
  }

  Widget _choices(ThemeData theme) => Column(
    key: const ValueKey<String>('choices'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      ProviderSignInButton.apple(
        busy: _asking == _Provider.apple,
        onPressed: _anyBusy ? null : () => _withProvider(_Provider.apple),
      ),
      const SizedBox(height: AppSpacing.md),
      ProviderSignInButton.google(
        busy: _asking == _Provider.google,
        onPressed: _anyBusy ? null : () => _withProvider(_Provider.google),
      ),
      const SizedBox(height: AppSpacing.md),
      AppOutlinedButton(
        label: 'Continue with email',
        icon: Icons.mail_outline,
        expand: true,
        onPressed: _anyBusy ? null : () => _showEmail(true),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        // O2. Apple's relay address is a different address, so Supabase has
        // nothing to join it to an existing account by.
        'Choosing Hide My Email with Apple starts a separate account.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textTertiary,
          height: 1.4,
        ),
      ),
    ],
  );

  Widget _emailForm(ThemeData theme) => Form(
    key: _form,
    child: Column(
      key: const ValueKey<String>('email'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextFormField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const <String>[AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email'),
          validator: (v) {
            final value = v?.trim() ?? '';
            if (value.isEmpty) return 'Enter your email.';
            // Deliberately loose. A strict pattern rejects valid addresses,
            // and the server is the real arbiter.
            if (!value.contains('@') || !value.contains('.')) {
              return 'That does not look like an email address.';
            }
            return null;
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _password,
          enabled: !_busy,
          obscureText: _obscure,
          autofillHints: <String>[
            _creating ? AutofillHints.newPassword : AutofillHints.password,
          ],
          decoration: InputDecoration(
            labelText: 'Password',
            suffixIcon: AppIconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              tooltip: _obscure ? 'Show password' : 'Hide password',
            ),
          ),
          onFieldSubmitted: (_) => _submit(),
          validator: (v) {
            final value = v ?? '';
            if (value.isEmpty) return 'Enter your password.';
            // Only enforced when creating. Refusing a short password at
            // sign-in would lock out anybody who made one before the rule
            // existed.
            if (_creating && value.length < 8) {
              return 'Use at least 8 characters.';
            }
            return null;
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        // Busy in place: a disabled button on a slow connection reads as "you
        // did something wrong" rather than "waiting".
        PrimaryButton(
          label: _creating ? 'Create account' : 'Sign in',
          busy: _busy,
          onPressed: _submit,
        ),
        const SizedBox(height: AppSpacing.xs),
        AppTextButton(
          label: _creating ? 'I already have an account' : 'Create an account',
          onPressed: _busy
              ? null
              : () => setState(() {
                  _creating = !_creating;
                  _error = null;
                  _notice = null;
                }),
        ),
        if (!_creating)
          AppTextButton(
            label: 'Forgot your password?',
            onPressed: _busy ? null : _resetPassword,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
          ),
        AppTextButton(
          label: 'Other ways to sign in',
          onPressed: _busy ? null : () => _showEmail(false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

/// The terms and privacy links under the sign-in form.
///
/// One sentence with two tappable halves rather than two buttons. Apple wants
/// the documents reachable from the point of account creation; a person wants
/// to know what they are agreeing to. A sentence does both, and two more
/// buttons under the primary action would compete with it.
class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  void _open(BuildContext context, LegalDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(document: document),
      ),
    );
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
          TextSpan(
            text: termsOfUse.title.toLowerCase(),
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _open(context, termsOfUse),
          ),
          const TextSpan(text: ' and the '),
          TextSpan(
            text: privacyPolicy.title.toLowerCase(),
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _open(context, privacyPolicy),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: base,
    );
  }
}
