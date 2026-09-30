import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../../core/brand.dart';
import '../../auth/domain/account.dart';
import '../domain/account_deleter.dart';

/// Account deletion, asked properly.
///
/// Guideline 5.1.1(v) requires in-app deletion of the account and its data for
/// any app that lets one be created. That is irreversible, so the gate is a
/// typed confirmation rather than a tap.
///
/// ## Why there is a choice here and not in run
///
/// One login serves the whole suite (ADR-0008), so "delete my account" names
/// two different requests: erase what this app holds, or erase the person from
/// MGKFitness entirely. Run offers neither — it sends no scope at all, which
/// the function reads as *everything*, so deleting a Run account silently takes
/// the lifter's sessions with it. Asking is the fix, and it is the honest
/// surface regardless: somebody who wants out of one app should not have to
/// give up the other to get it.
///
/// The scoped choice still cannot promise the login survives, and this screen
/// does not pretend otherwise. If Run holds nothing, a profile with nothing
/// behind it is not kept on somebody's behalf. The server decides; the outcome
/// screen says which happened.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    required this.auth,
    required this.deleter,
    this.onSignedOut,
    this.onAccountGone,
  });

  final AuthService auth;
  final AccountDeleter deleter;

  /// The login is gone, and the training on this phone belongs to nobody now.
  ///
  /// Called before signing out, only when the server removed the login. Left
  /// out, the phone would stay recorded as the deleted account's, and the
  /// same person making a new one would be asked to erase their own sessions
  /// to use it.
  final Future<void> Function()? onAccountGone;

  /// Where to go once the session has ended. Defaults to unwinding to the app
  /// root, so what remains is an app with no account — which is a working app,
  /// because tracking never needed one.
  final VoidCallback? onSignedOut;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const String _phrase = 'DELETE';

  final TextEditingController _confirm = TextEditingController();

  /// Starts on the narrower of the two. A destructive screen should not open
  /// with the most destructive option already chosen — the wider one is a
  /// decision to make, not a default to accept.
  DeletionScope _scope = DeletionScope.liftOnly;

  bool _busy = false;
  String? _error;
  AccountDeletionResult? _result;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _armed => _confirm.text.trim().toUpperCase() == _phrase;

  Future<void> _delete() async {
    if (!_armed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.deleter.deleteAccount(scope: _scope);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
    } on AccountDeletionException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _finish() async {
    if (_result?.accountDeleted ?? false) await widget.onAccountGone?.call();
    await widget.auth.signOut();
    if (!mounted) return;
    final onSignedOut = widget.onSignedOut;
    if (onSignedOut != null) {
      onSignedOut();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete account'),
        // No way back once it has happened. The only route out of the done
        // state is the button that ends the session, so the app cannot be left
        // holding a token for an account that no longer exists.
        automaticallyImplyLeading: result == null && !_busy,
      ),
      body: SafeArea(
        child: result == null ? _buildConfirm(context) : _buildDone(result),
      ),
    );
  }

  Widget _buildConfirm(BuildContext context) {
    final theme = Theme.of(context);
    final email = widget.auth.current?.email;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: <Widget>[
        // Arrives, but only just. This screen asks somebody to confirm
        // something irreversible, and a flourish would be the wrong register —
        // the warning should be there when they look, not perform its way in.
        Entrance(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.danger,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'This cannot be undone.',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        const SectionLabel('How much', color: AppColors.textTertiary),
        const SizedBox(height: AppSpacing.sm),
        _ScopeChoice(
          // Keyed by the scope so a test can tap one without matching the
          // button, which deliberately carries the same words.
          key: const ValueKey<DeletionScope>(DeletionScope.liftOnly),
          scope: DeletionScope.liftOnly,
          selected: _scope,
          enabled: !_busy,
          onChanged: (s) => setState(() => _scope = s),
          title: 'Delete my $kAppName data',
          body:
              'Your sessions, exercises and sets, your plans, and your coach '
              'conversations. Your $kPlatformName account stays, so '
              '$kPlatformName: Run keeps working.',
        ),
        _ScopeChoice(
          key: const ValueKey<DeletionScope>(DeletionScope.everything),
          scope: DeletionScope.everything,
          selected: _scope,
          enabled: !_busy,
          onChanged: (s) => setState(() => _scope = s),
          title: 'Delete my whole $kPlatformName account',
          body:
              'Everything above, everything $kPlatformName: Run holds, and the '
              'login itself. You will not be able to sign in to either app.',
        ),

        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.cardAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionLabel(
                'About your login',
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                // Said before the deletion, not discovered after it. Somebody
                // choosing the narrow option is entitled to know it may still
                // take their login, because we are not going to keep a profile
                // that has nothing behind it on their behalf.
                _scope == DeletionScope.liftOnly
                    ? 'Your login is your $kPlatformName account, shared with '
                          '$kPlatformName: Run. If Run holds no data, there is '
                          'nothing left for the account to be for, so it goes '
                          'too. We will tell you which happened.'
                    : 'This removes the account itself, so anything '
                          '$kPlatformName: Run holds goes with it. If you only '
                          'want out of this app, choose the first option.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.lg),
        Text(
          'What is on this phone is not touched. Deleting removes it from our '
          'servers — not hidden, actually deleted. Uninstalling the app is '
          'what clears this device.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
            height: 1.5,
          ),
        ),

        const SizedBox(height: AppSpacing.xl),
        if (email != null) ...<Widget>[
          Text(
            'Signed in as $email',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Text('Type $_phrase to confirm', style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _confirm,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: _phrase),
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
          // Names what is about to happen rather than saying "Delete", so the
          // last thing read before the tap is the scope that was chosen.
          label: _scope == DeletionScope.liftOnly
              ? 'Delete my $kAppName data'
              : 'Delete my account',
          busy: _busy,
          onPressed: _armed ? _delete : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextButton(
          label: 'Keep my account',
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildDone(AccountDeletionResult result) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: <Widget>[
        Icon(
          result.loginCouldNotBeRemoved
              ? Icons.error_outline
              : Icons.check_circle_outline,
          size: 40,
          color: result.loginCouldNotBeRemoved
              ? AppColors.danger
              : AppColors.success,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Your data is deleted', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        Text(
          _outcome(result),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        PrimaryButton(label: 'Done', onPressed: _finish),
      ],
    );
  }

  /// What actually happened, which is not always what was asked for.
  String _outcome(AccountDeletionResult result) {
    const String gone =
        'Your sessions, exercises and sets, your plans and your coach '
        'conversations have been removed from our servers.';

    if (result.loginCouldNotBeRemoved) {
      return '$gone Your login could not be removed, though — email '
          'hello@mgkcodes.com and we will finish it by hand.';
    }
    if (result.loginRetainedForOtherApp) {
      return '$gone Your $kPlatformName account is still active because '
          '$kPlatformName: Run is using it, which is what you asked for.';
    }
    if (result.accountDeleted) {
      return _scope == DeletionScope.liftOnly
          // Asked for the narrow one and got the wide one, because there was
          // nothing left to keep. Said plainly rather than glossed.
          ? '$gone Your $kPlatformName account went too: nothing else was '
                'using it, so there was nothing left for it to be for.'
          : '$gone Everything $kPlatformName: Run held is gone as well, along '
                'with your login.';
    }
    return gone;
  }
}

/// One of the two scopes, as a card you can select.
///
/// A radio rather than two buttons: both options are destructive, so the screen
/// must not offer two ways to fire. One choice, then one confirmed action.
class _ScopeChoice extends StatelessWidget {
  const _ScopeChoice({
    super.key,
    required this.scope,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    required this.title,
    required this.body,
  });

  final DeletionScope scope;
  final DeletionScope selected;
  final bool enabled;
  final ValueChanged<DeletionScope> onChanged;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = scope == selected;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: PressScale(
        enabled: enabled,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? () => onChanged(scope) : null,
            borderRadius: AppRadius.cardAll,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                borderRadius: AppRadius.cardAll,
                color: AppColors.surface,
                border: Border.all(
                  // The selected edge is the danger colour on the wider scope
                  // only. Greyscale is the rule (ADR-0009) and status is the
                  // sanctioned exception — "this one takes everything" is status.
                  color: isSelected
                      ? (scope == DeletionScope.everything
                            ? AppColors.danger
                            : AppColors.textSecondary)
                      : AppColors.elevated,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          body,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
