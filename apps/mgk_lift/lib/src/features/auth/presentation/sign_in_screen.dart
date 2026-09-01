import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../legal/domain/legal_copy.dart';
import '../../legal/domain/legal_document.dart';
import '../../legal/presentation/legal_document_screen.dart';
import '../domain/account.dart';

/// Sign in, or make an account.
///
/// **One screen for both**, toggled, rather than two. The fields are identical
/// and the difference is one word on a button; two screens would mean two
/// layouts, two validation paths and a "wrong screen" dead end for anybody who
/// tapped the wrong entry point.
///
/// This is never in anybody's way. Tracking works signed out, and the screen
/// says so at the bottom — somebody who opened it by accident should be able to
/// leave without feeling they have lost something.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth, this.pendingWorkouts = 0});

  final AuthService auth;

  /// How many sessions exist only on this phone. Shown as the reason to bother,
  /// because it is the true one and it is specific.
  final int pendingWorkouts;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  bool _creating = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
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
      if (!mounted) return;
      Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Backing out mid-request would leave the lifter on Track not knowing
    // whether they are signed in — the request completes either way, and the
    // stream that reports it fires into a disposed screen. Two seconds of a
    // disabled arrow is the cheaper confusion.
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(_creating ? 'Create account' : 'Sign in')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      constraints.maxHeight - AppSpacing.lg - AppSpacing.xxl,
                ),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        _creating ? 'Create an account' : 'Welcome back',
                        style: theme.textTheme.headlineSmall,
                      ),
                      // Only when there is something to say. Signing in
                      // needs no explanation, and a paragraph under the
                      // headline that exists to fill the space is how the
                      // screen started arguing for an account in the first
                      // place.
                      if (_reason() case final String reason) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          reason,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),

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
                          // Deliberately loose. A strict pattern rejects valid
                          // addresses, and the server is the real arbiter.
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
                          _creating
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: AppIconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                          ),
                        ),
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) {
                          final value = v ?? '';
                          if (value.isEmpty) return 'Enter your password.';
                          // Only enforced when creating. Refusing a short
                          // password at sign-in would lock out anybody who made
                          // one before the rule existed.
                          if (_creating && value.length < 8) {
                            return 'Use at least 8 characters.';
                          }
                          return null;
                        },
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
                      if (_busy)
                        // A disabled button on a slow connection reads as "you
                        // did something wrong" rather than "waiting".
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                            ),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else
                        PrimaryButton(
                          label: _creating ? 'Create account' : 'Sign in',
                          onPressed: _submit,
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextButton(
                        label: _creating
                            ? 'I already have an account'
                            : 'Create an account',
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

                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        // The escape hatch. Somebody who opened this by accident
                        // should be able to leave without feeling they have lost
                        // something, because they have not.
                        'You do not need an account to track your training.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                          height: 1.4,
                        ),
                      ),

                      // Required wherever an account can be created, and this
                      // screen is the only place it can be. Shown in both modes
                      // rather than only when creating: somebody signing in on a
                      // new phone is re-accepting the same terms, and a link
                      // that appears and disappears reads as a trick.
                      const SizedBox(height: AppSpacing.lg),
                      const _LegalLinks(),
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

  /// What is worth saying under the headline, or null when nothing is.
  ///
  /// Signing in gets nothing: somebody on this screen with an account knows
  /// what it does, and the app telling them their data will be there is the
  /// kind of line that reads as filler at best.
  ///
  /// Creating gets one fact, and only when there is one — sessions that exist
  /// in a single place. That is state the person may not have, not an argument
  /// for the account.
  String? _reason() {
    if (!_creating) return null;
    final n = widget.pendingWorkouts;
    if (n == 0) return null;
    return '$n session${n == 1 ? '' : 's'} ${n == 1 ? 'is' : 'are'} on this '
        'phone only.';
  }
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
