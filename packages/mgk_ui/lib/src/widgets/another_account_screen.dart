import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'app_buttons.dart';
import 'primary_button.dart';

/// Shown instead of the app when an account signs in on a phone whose training
/// belongs to a different one.
///
/// **Two ways out and no third.** Carrying on with the training as it is would
/// be the bug this exists to stop: a backup pushing one person's training into
/// another's account, the coach briefed from somebody else's notes, the log
/// and the photo on show to whoever signed in. So the account that just
/// arrived either erases what is here and starts clean, or signs out and
/// leaves it exactly as it was.
///
/// Nothing restores, backs up or talks to the coach while this is on screen;
/// see `LocalDataGuard` in mgk_auth. It cannot be dismissed, because every way
/// of dismissing it is one of the two answers.
///
/// Written for Run (`ab02080`) and shared when Lift needed the same question:
/// only [whatIsHere] differs between the apps.
class AnotherAccountScreen extends StatefulWidget {
  const AnotherAccountScreen({
    super.key,
    required this.email,
    required this.whatIsHere,
    required this.onErase,
    required this.onSignOut,
  });

  /// Who just signed in. Null only for an account with no address, which this
  /// app does not create; the sentence then names nobody rather than guessing.
  final String? email;

  /// What this app keeps, as the start of a sentence: `The runs, plan and
  /// coach conversations`, `The sessions, workouts and photos`.
  final String whatIsHere;

  /// Erases this phone's training and continues as the account signed in.
  /// Throws when the training could not be erased.
  final Future<void> Function() onErase;

  final Future<void> Function() onSignOut;

  @override
  State<AnotherAccountScreen> createState() => _AnotherAccountScreenState();
}

class _AnotherAccountScreenState extends State<AnotherAccountScreen> {
  bool _erasing = false;
  bool _signingOut = false;
  String? _error;

  bool get _busy => _erasing || _signingOut;

  Future<void> _erase() async {
    setState(() {
      _erasing = true;
      _error = null;
    });
    try {
      await widget.onErase();
    } on Object {
      if (!mounted) return;
      setState(() {
        _erasing = false;
        _error =
            "This phone's training could not be erased. Try again, or sign "
            'out.';
      });
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _signingOut = true;
      _error = null;
    });
    await widget.onSignOut();
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = widget.email;
    final account = email ?? 'this account';
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textSecondary,
      height: 1.5,
    );
    final dim = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: 1.5,
    );

    return PopScope<void>(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxl,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            children: <Widget>[
              Text(
                "This phone has another account's training on it",
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '${widget.whatIsHere} on this phone were recorded under a '
                'different account. To continue as $account, erase them from '
                'this phone first.',
                style: body,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                // Both halves, because the person choosing is not the person
                // whose training it is, and one of the two is permanent.
                'Erasing only touches this phone. Anything that account backed '
                'up stays backed up; anything it did not is gone for good. '
                'Signing out leaves this phone as it is.',
                style: dim,
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.danger,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              DestructiveButton(
                label: "Erase this phone's training and continue as $account",
                busy: _erasing,
                onPressed: _busy ? null : _erase,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextButton(
                label: 'Sign out',
                busy: _signingOut,
                onPressed: _busy ? null : _signOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
