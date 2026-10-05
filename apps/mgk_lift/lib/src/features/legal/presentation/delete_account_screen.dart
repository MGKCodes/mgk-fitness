import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../../core/brand.dart';
import '../../auth/domain/account.dart';
import '../domain/account_deleter.dart';

/// The other app, by its full name: the one that keeps the login when this
/// app's data is all that goes.
const String _run = '$kPlatformName: Run';

/// Account deletion, asked properly.
///
/// Guideline 5.1.1(v) requires in-app deletion of the account and its data for
/// any app that lets one be created. That is irreversible, so the gate is a
/// typed confirmation rather than a tap.
///
/// ## Why there is a choice
///
/// One login serves the whole suite (ADR-0008), so "delete my account" names
/// two different requests: erase what this app holds, or erase the person from
/// MGKFitness entirely. Asking is the honest surface: somebody who wants out of
/// one app should not have to give up the other to get it. Since 4 October
/// 2026 the choice, the note about the login and the phone's copy are the
/// suite's own widgets ([DeletionChoice], [NoticePanel], [PhoneCopySwitch]),
/// so Run's screen asks in the same words from its 1.0.1.
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
    this.eraseThisPhone,
    this.onManageSubscription,
    this.platform,
  });

  final AuthService auth;
  final AccountDeleter deleter;

  /// The store's page for the subscription. **Given only to somebody
  /// subscribed**, for whom the screen says, before the tap and again after
  /// it, that deleting does not cancel what the store bills (5 October 2026,
  /// as Run's always has).
  final VoidCallback? onManageSubscription;

  /// Which store's name to use. Injected for tests; the device's otherwise.
  final TargetPlatform? platform;

  /// Erases this phone's training and leaves it unclaimed
  /// (`LocalDataGuard.erase`). Given, the screen offers to erase the phone's
  /// copy as well, as Run's does, and on by default; null, the phone is said
  /// to be untouched.
  final Future<void> Function()? eraseThisPhone;

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

  /// Whether to erase this phone's copy too, where that is offered.
  bool _erasePhone = true;

  /// What became of this phone's copy, once the deletion is done.
  _PhoneCopy _phoneCopy = _PhoneCopy.notMentioned;

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

  /// Deleting does not cancel the subscription, with the way to: the
  /// suite's words. Null for somebody not subscribed.
  Widget? get _stillBilling => switch (widget.onManageSubscription) {
    final VoidCallback manage => StillBillingNotice(
      store: storeName(widget.platform ?? defaultTargetPlatform),
      onManage: manage,
    ),
    null => null,
  };

  Future<void> _delete() async {
    if (!_armed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Read before the first await: what happens after the server answers must
    // happen whether or not this screen is still there to see it.
    final erase = widget.eraseThisPhone;
    final erasePhone = _erasePhone;
    try {
      final result = await widget.deleter.deleteAccount(scope: _scope);
      var phoneCopy = _PhoneCopy.notMentioned;
      if (erase != null) {
        if (!erasePhone) {
          phoneCopy = _PhoneCopy.kept;
        } else {
          try {
            await erase();
            phoneCopy = _PhoneCopy.erased;
          } on Object {
            phoneCopy = _PhoneCopy.eraseFailed;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
        _phoneCopy = phoneCopy;
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
    // An erased phone is already unclaimed; one that kept its copy, or never
    // had the choice, is released when the account it belonged to has gone.
    if ((_result?.accountDeleted ?? false) && _phoneCopy != _PhoneCopy.erased) {
      await widget.onAccountGone?.call();
    }
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
        // Which app is asking, as the paywall says it: the two apps look alike
        // on purpose, and this screen can take the other one's data too.
        const AppIdentityRow(
          icon: AssetImage('assets/images/brand/app_icon.png'),
          name: kProductName,
        ),
        const SizedBox(height: AppSpacing.lg),
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
        // Before the choice, where Run says it: the thing a subscriber most
        // needs to know before deleting is that it will not stop the bills.
        if (_stillBilling case final Widget notice) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          notice,
        ],
        const SizedBox(height: AppSpacing.xl),

        // The suite's two choices, the same words in Run's screen.
        DeletionChoice(
          wide: _scope == DeletionScope.everything,
          enabled: !_busy,
          onChanged: (wide) => setState(
            () => _scope = wide
                ? DeletionScope.everything
                : DeletionScope.liftOnly,
          ),
          otherApp: _run,
          holds:
              'Your sessions, exercises and sets, your plans, your progress '
              'photos and your coach conversations.',
        ),

        const SizedBox(height: AppSpacing.md),
        // Said before the deletion, not discovered after it. Somebody choosing
        // the narrow option is entitled to know it may still take their
        // login, because we are not going to keep an account that has nothing
        // behind it on their behalf.
        NoticePanel(
          label: 'About your login',
          text: deletionLoginNote(
            wide: _scope == DeletionScope.everything,
            otherApp: _run,
          ),
        ),

        const SizedBox(height: AppSpacing.lg),
        if (widget.eraseThisPhone != null)
          PhoneCopySwitch(
            value: _erasePhone,
            onChanged: _busy ? null : (on) => setState(() => _erasePhone = on),
            // What `PhoneTrainingData.eraseAll` removes, and no more: the
            // coach's conversations live on the server, never on the phone.
            erasing:
                'Your sessions, saved workouts, plan and progress photos are '
                'removed from this phone as well.',
            // Rows already sent stay marked as sent, so signing in again does
            // not put them back: what is kept is this phone's alone.
            keeping:
                'Your sessions stay on this phone, and nothing on it is '
                'backed up any more.',
          )
        else
          Text(
            'What is on this phone is not touched. Deleting removes it from '
            'our servers — not hidden, actually deleted. Uninstalling the app '
            'is what clears this device.',
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
              ? "Delete this app's data"
              : 'Delete my whole account',
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
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textSecondary,
      height: 1.5,
    );
    final phone = _phoneSentence;
    // A login still there for any reason but the other app is one that could
    // not be removed, which is how the outcome sentence reads it too.
    final loginStuck =
        !result.accountDeleted && !result.loginRetainedForOtherApp;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: <Widget>[
        Icon(
          loginStuck ? Icons.error_outline : Icons.check_circle_outline,
          size: 40,
          color: loginStuck ? AppColors.danger : AppColors.success,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          // Run's rule: "Your data is deleted" over a phone still holding
          // every session is true of the server and false of the thing in the
          // lifter's hand.
          _phoneCopy == _PhoneCopy.kept || _phoneCopy == _PhoneCopy.eraseFailed
              ? 'Deleted from our servers'
              : 'Your data is deleted',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(_outcome(result), style: body),
        if (phone != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(phone, style: body),
        ],
        // Again once it is done, because this is when it will be acted on.
        if (_stillBilling case final Widget notice) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          notice,
        ],
        const SizedBox(height: AppSpacing.xxl),
        PrimaryButton(label: 'Done', onPressed: _finish),
      ],
    );
  }

  /// What actually happened, which is not always what was asked for, in the
  /// suite's words.
  String _outcome(AccountDeletionResult result) => deletionOutcome(
    removed:
        'Your sessions, exercises and sets, your plans, your progress photos '
        'and your coach conversations have been removed from our servers.',
    wide: _scope == DeletionScope.everything,
    accountDeleted: result.accountDeleted,
    keptForOtherApp: result.loginRetainedForOtherApp,
    otherApp: _run,
    supportEmail: kSupportEmail,
  );

  /// What became of this phone's copy, in Run's words for Run's cases.
  String? get _phoneSentence => switch (_phoneCopy) {
    _PhoneCopy.notMentioned => null,
    _PhoneCopy.erased => "This phone's copy has been erased too.",
    _PhoneCopy.kept =>
      'Your sessions are still on this phone, and nothing on it is backed up '
          'any more.',
    _PhoneCopy.eraseFailed =>
      "This phone's copy could not be erased, so your sessions are still on "
          'it. Deleting the app removes them.',
  };
}

/// What became of this phone's copy of the training.
enum _PhoneCopy {
  /// No eraser to offer: the preview harness, and tests not about it.
  notMentioned,
  erased,
  kept,
  eraseFailed,
}
