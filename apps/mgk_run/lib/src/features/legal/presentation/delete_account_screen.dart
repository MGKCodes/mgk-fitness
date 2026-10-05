import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../../../core/brand.dart';
import '../../auth/data/auth_repository.dart';
import '../../coaching/data/entitlement_repository.dart';
import '../../coaching/data/purchase_client.dart';
import '../../coaching/domain/coach_subscription.dart';
import '../../coaching/domain/manage_subscription.dart';
import '../../coaching/presentation/manage_subscription_link.dart';
import '../../settings/domain/backup_consent.dart';
import 'package:mgk_auth/mgk_auth.dart';
import '../../settings/presentation/phone_scope.dart';
import '../data/account_deletion_service.dart';
import '../domain/account_deleter.dart';

/// The other app, by its full name: the one that keeps the login when this
/// app's data is all that goes.
const String _lift = '$kPlatformName: Lift';

/// Where a runner writes to us, and where a login that would not go is
/// finished by hand.
const String _support = 'run@mgkfitness.mgkcodes.com';

/// Account deletion, confirmed properly.
///
/// `docs/compliance.md` requires the user to be able to delete their account and
/// all associated data and have it *actually removed*. That is irreversible, so
/// the gate is a typed confirmation, not a tap: the runner must type `DELETE`.
/// Nothing leaves the screen until they do.
///
/// ## Two ways to delete, as in Lift (1.0.1)
///
/// One login serves the suite (ADR-0008), so "delete my account" names two
/// requests: this app's data, or the whole MGKFitness account and everything
/// in both apps. Until 1.0.1 this screen offered only the first and told the
/// runner to email us for the second. It now asks, in the suite's own widgets
/// ([DeletionChoice], [NoticePanel], [PhoneCopySwitch]), so the two apps ask
/// in the same words, and it opens on the narrower choice.
///
/// Afterwards the outcome is stated plainly, including the case the shared
/// login survives because Lift is using it, and what became of this phone's
/// copy.
///
/// ## Deleting the account used to leave the phone ready to put it back
///
/// A successful deletion signed out and said "Your data is deleted", and that
/// was all. The backup answer on the phone still said yes, so signing back in
/// -- the login is kept whenever Lift holds data -- or making a new account on
/// the same phone backfilled every deleted run straight back to the server.
/// Now a confirmed deletion resets that answer, removes this app's keys from a
/// login that survives, ends the session, and erases this phone's copy unless
/// the runner chose to keep it; the screen says which of those happened.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    this.auth = const AuthRepository(),
    this.deleter = const AccountDeletionService(),
    this.onSignedOut,
    this.consentStore,
    this.localData,
    this.entitlements = const SupabaseEntitlements(),
    this.purchases,
    this.openUrl,
  });

  final AuthRepository auth;
  final AccountDeleter deleter;

  /// Read once, on open, to say whether deleting leaves a subscription
  /// renewing. Never to decide anything: the store bills whatever this says.
  final EntitlementRepository entitlements;

  /// For the store's management page on an iPhone. Null looks in
  /// [PhoneScope].
  final PurchaseClient? purchases;

  /// Opens a store page in the browser. Null is the real browser.
  final UrlOpener? openUrl;

  /// Where to go once the runner has read the outcome. Defaults to unwinding
  /// to the app root, where the signed-out app is waiting.
  final VoidCallback? onSignedOut;

  /// The backup answer to reset. Null looks in [PhoneScope], which is where
  /// the app keeps it: this screen is reached from Account and from Privacy &
  /// legal, and only the first could pass it.
  final BackupConsentStore? consentStore;

  /// Whose training is on this phone, and the eraser for it. Null looks in
  /// [PhoneScope]; with neither, the phone is not mentioned at all.
  final LocalDataGuard? localData;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const _phrase = 'DELETE';

  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  AccountDeletionResult? _result;

  /// Starts on the narrower of the two. A destructive screen should not open
  /// with the most destructive option already chosen.
  DeletionScope _scope = DeletionScope.runOnly;

  /// Whether to erase this phone's copy as well. **On by default** here, where
  /// signing out has it off: somebody deleting their account has asked for
  /// their data to go, and a copy left on the phone is the part of that request
  /// they are least likely to think of.
  bool _erasePhone = true;

  /// What became of this phone's copy, once the deletion is done.
  _PhoneCopy _phoneCopy = _PhoneCopy.notMentioned;

  /// The subscription as it stood when the screen opened. Kept, rather than
  /// read again for the done screen, because by then the account is gone and
  /// the read would say there was never one -- while the store goes on billing.
  CoachSubscription? _subscription;
  late final Future<void> _subscriptionRead = _readSubscription();

  Future<void> _readSubscription() async {
    final CoachSubscription read;
    try {
      read = await widget.entitlements.subscription();
    } on Object {
      return;
    }
    if (!mounted) return;
    setState(() => _subscription = read);
  }

  /// Whether deleting leaves a subscription that will keep charging: paid up,
  /// or a payment the store is still chasing. An ended one charges nothing.
  bool get _stillBilling => switch (_subscription?.standing) {
    SubscriptionStanding.active || SubscriptionStanding.billingRetry => true,
    _ => false,
  };

  BackupConsentStore? get _consentStore =>
      widget.consentStore ?? PhoneScope.maybeOf(context)?.consent;

  LocalDataGuard? get _localData =>
      widget.localData ?? PhoneScope.maybeOf(context)?.localData;

  bool get _wide => _scope == DeletionScope.everything;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
    unawaited(_subscriptionRead);
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _armed => _confirm.text.trim().toUpperCase() == _phrase;

  Future<void> _delete() async {
    if (!_armed || _busy) return;
    // Read before the first await: what happens after the server answers must
    // happen whether or not this screen is still there to see it.
    final consent = _consentStore;
    final localData = _localData;
    final erasePhone = _erasePhone;
    final scope = _scope;
    setState(() {
      _busy = true;
      _error = null;
    });
    // The done screen repeats the billing warning, and it can only do that if
    // the read has landed. It is bounded and was started when the screen
    // opened, so this is almost always already done.
    await _subscriptionRead;
    try {
      final result = await widget.deleter.deleteAccount(scope: scope);
      final phoneCopy = await _afterDeletion(
        result,
        consent: consent,
        localData: localData,
        erasePhone: erasePhone,
      );
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

  /// Everything a confirmed deletion owes the phone, in the order it has to
  /// happen.
  ///
  /// **The session ends here, not when the runner taps Done.** It used to
  /// wait for Done, so the outcome could be read first -- which this screen
  /// still allows, being a route over the app rather than part of it. What the
  /// wait cost was everything after it: an app closed on this screen kept a
  /// session to an account that no longer existed, and an erased phone
  /// rebuilt its shell for that session, claimed itself for it and asked
  /// whether to back it up.
  Future<_PhoneCopy> _afterDeletion(
    AccountDeletionResult result, {
    required BackupConsentStore? consent,
    required LocalDataGuard? localData,
    required bool erasePhone,
  }) async {
    // First, so nothing on the phone can be sent anywhere again on the
    // strength of a yes given to an account that is gone.
    await consent?.write(BackupConsent.unknown);
    // A login kept for Lift still carries this app's keys, and clearing them
    // needs the session, so before signing out. Best-effort: the data is
    // already gone, which is what the runner asked for.
    if (!result.accountDeleted) {
      try {
        await widget.auth.clearRunMetadata();
      } on Object {
        // Deliberate: see above.
      }
    }
    try {
      await widget.auth.signOut();
    } on Object {
      // A sign-out that could not reach the server has still ended the
      // session here, which is the half that matters to this phone.
    }
    if (localData == null) return _PhoneCopy.notMentioned;
    if (!erasePhone) {
      // Kept, and nobody's: the account it belonged to has gone, so the next
      // account to sign in -- this runner's own, if they make one again --
      // claims it rather than being told it is somebody else's.
      await localData.release();
      return _PhoneCopy.kept;
    }
    try {
      await localData.erase();
      return _PhoneCopy.erased;
    } on Object {
      await localData.release();
      return _PhoneCopy.eraseFailed;
    }
  }

  void _manageSubscription() => unawaited(
    openManageSubscription(
      context,
      _subscription!,
      purchases: widget.purchases,
      open: widget.openUrl,
    ),
  );

  void _finish() {
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
        automaticallyImplyLeading: result == null && !_busy,
      ),
      body: SafeArea(
        child: result == null ? _buildConfirm(context) : _buildDone(result),
      ),
    );
  }

  Widget _buildConfirm(BuildContext context) {
    final theme = Theme.of(context);
    final email = widget.auth.currentEmail;
    final localData = _localData;

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
        if (_stillBilling) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          _StillBilling(
            subscription: _subscription!,
            onManage: _manageSubscription,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),

        // The suite's two choices, the same words in Lift's screen.
        DeletionChoice(
          wide: _wide,
          enabled: !_busy,
          onChanged: (wide) => setState(
            () => _scope = wide
                ? DeletionScope.everything
                : DeletionScope.runOnly,
          ),
          otherApp: _lift,
          // What is actually erased and actually sensitive. It once promised
          // "the date of birth and weight you gave the app", which this app
          // has never asked for -- on the one page where a runner is asked to
          // trust a claim about deletion. The coach's conversations carry
          // injury notes and how somebody said they were feeling, which is
          // the most personal thing this app holds.
          holds:
              'Your runs, routes and splits, your runner profile and plans, '
              'and your coach conversations, with what the coach remembered '
              'about you.',
        ),

        const SizedBox(height: AppSpacing.md),
        // Said before the deletion, not discovered after it.
        NoticePanel(
          label: 'About your login',
          text: deletionLoginNote(wide: _wide, otherApp: _lift),
        ),

        if (localData != null) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          PhoneCopySwitch(
            value: _erasePhone,
            onChanged: _busy ? null : (on) => setState(() => _erasePhone = on),
            erasing:
                'Your runs, plan, coach conversations, name and photo are '
                'removed from this phone as well.',
            keeping:
                'Your runs stay on this phone, and nothing on it is backed '
                'up any more.',
          ),
        ],
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
          label: _wide ? 'Delete my whole account' : "Delete this app's data",
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: <Widget>[
        Icon(
          result.loginNotRemoved
              ? Icons.error_outline
              : Icons.check_circle_outline,
          size: 40,
          color: result.loginNotRemoved ? AppColors.danger : AppColors.success,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          // "Your data is deleted" over a phone still holding every run was
          // true of the server and false of the thing in the runner's hand.
          _phoneCopy == _PhoneCopy.kept || _phoneCopy == _PhoneCopy.eraseFailed
              ? 'Deleted from our servers'
              : 'Your data is deleted',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(_serverSentence(result), style: body),
        if (phone != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(phone, style: body),
        ],
        if (_stillBilling) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          _StillBilling(
            subscription: _subscription!,
            onManage: _manageSubscription,
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        PrimaryButton(label: 'Done', onPressed: _finish),
      ],
    );
  }

  /// What the server did, including the login -- which was said wrongly for
  /// two of the three answers the server can give, until the suite's sentence
  /// replaced this app's own.
  String _serverSentence(AccountDeletionResult result) => deletionOutcome(
    removed:
        'Your runs, routes and splits, your runner profile and plans, and '
        'your coach conversations have been removed from our servers.',
    wide: _wide,
    accountDeleted: result.accountDeleted,
    keptForOtherApp: result.loginRetainedForSiblingApp,
    otherApp: _lift,
    supportEmail: _support,
  );

  String? get _phoneSentence => switch (_phoneCopy) {
    _PhoneCopy.notMentioned => null,
    _PhoneCopy.erased => "This phone's copy has been erased too.",
    _PhoneCopy.kept =>
      'Your runs are still on this phone, and nothing on it is backed up any '
          'more.',
    _PhoneCopy.eraseFailed =>
      "This phone's copy could not be erased, so your runs are still on it. "
          'Deleting the app removes them.',
  };
}

/// **Deleting the account does not stop the store charging for it**, and the
/// screen said nothing about that.
///
/// The subscription is between the runner and Apple or Google; deleting the
/// data the coach runs on does not end it, and nothing on this side can. Apple's
/// account-deletion guidance asks for exactly this to be said, and for the way
/// to cancel to be offered where it is said -- before the runner confirms, and
/// again once it is done, because the second is when they will act on it.
class _StillBilling extends StatelessWidget {
  const _StillBilling({required this.subscription, required this.onManage});

  final CoachSubscription subscription;
  final VoidCallback onManage;

  /// The store that bills it, which is not always this phone's: a runner
  /// who subscribed on an iPhone and deletes from an Android phone is told
  /// the App Store. The words are the suite's, shared with Lift's screen.
  @override
  Widget build(BuildContext context) => StillBillingNotice(
    store: billingStoreFor(subscription, defaultTargetPlatform).label,
    onManage: onManage,
  );
}

/// What became of this phone's copy of the training.
enum _PhoneCopy {
  /// No eraser to offer: the preview harness, and tests not about it.
  notMentioned,
  erased,
  kept,
  eraseFailed,
}
