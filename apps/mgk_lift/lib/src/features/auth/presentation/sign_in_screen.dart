import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

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
  const SignInScreen({
    super.key,
    required this.auth,
    this.pendingWorkouts = 0,
  });

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
        await widget.auth.signUp(
          email: _email.text,
          password: _password.text,
        );
      } else {
        await widget.auth.signIn(
          email: _email.text,
          password: _password.text,
        );
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

    return Scaffold(
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
                minHeight: constraints.maxHeight - AppSpacing.lg - AppSpacing.xxl,
              ),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      _creating
                          ? 'Back up your training'
                          : 'Welcome back',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _reason(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
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
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
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
                    PrimaryButton(
                      label: _creating ? 'Create account' : 'Sign in',
                      onPressed: _busy ? null : _submit,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _creating = !_creating;
                              _error = null;
                              _notice = null;
                            }),
                      child: Text(
                        _creating
                            ? 'I already have an account'
                            : 'Create an account',
                      ),
                    ),
                    if (!_creating)
                      TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                        ),
                        child: const Text('Forgot your password?'),
                      ),

                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      // The escape hatch. Somebody who opened this by accident
                      // should be able to leave without feeling they have lost
                      // something, because they have not.
                      'You do not need an account to track your training. '
                      'This is for backing it up.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _reason() {
    if (!_creating) {
      return 'Sign in and your training comes back, on this phone or any '
          'other.';
    }
    final n = widget.pendingWorkouts;
    return n == 0
        ? 'Your training is only on this phone. An account backs it up and '
              'follows you to a new one.'
        // Specific beats general. "9 sessions exist nowhere else" is a reason;
        // "back up your data" is a category.
        : '$n session${n == 1 ? '' : 's'} ${n == 1 ? 'exists' : 'exist'} only '
              'on this phone. An account backs ${n == 1 ? 'it' : 'them'} up.';
  }
}
