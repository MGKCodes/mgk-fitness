import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../coaching/data/entitlement_repository.dart';
import '../../coaching/data/purchase_client.dart';
import '../../coaching/domain/coach_subscription.dart';
import '../../coaching/domain/manage_subscription.dart';
import '../../coaching/presentation/manage_subscription_link.dart';
import '../../settings/domain/backup_consent.dart';
import '../../settings/domain/local_data.dart';
import '../../settings/presentation/phone_scope.dart';
import '../data/account_deletion_service.dart';
import '../domain/account_deleter.dart';

/// Account deletion, confirmed properly.
///
/// `docs/compliance.md` requires the user to be able to delete their account and
/// all associated data and have it *actually removed*. That is irreversible, so
/// the gate is a typed confirmation, not a tap: the runner must type `DELETE`.
/// Nothing leaves the screen until they do.
///
/// Afterwards the outcome is stated plainly, including the case the shared
/// MGKCodes login survives because Liftio is using it (ADR-0008), and what
/// became of this phone's copy.
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
    setState(() {
      _busy = true;
      _error = null;
    });
    // The done screen repeats the billing warning, and it can only do that if
    // the read has landed. It is bounded and was started when the screen
    // opened, so this is almost always already done.
    await _subscriptionRead;
    try {
      final result = await widget.deleter.deleteAccount();
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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
              const SizedBox(width: 12),
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
          const SizedBox(height: 20),
          _StillBilling(
            subscription: _subscription!,
            onManage: _manageSubscription,
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'Deleting removes all of your data from our servers — not '
          'hidden, actually deleted:',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        const _DeletedItem('Every run, with its route points and splits'),
        const _DeletedItem('Your runner profile and generated plans'),
        // Was "The date of birth and weight you gave the app". This app has
        // never asked for either — `core.profiles.dob` and `weight_kg` exist
        // and belong to Liftio — so the screen promised to delete two things
        // that were never collected, on the one page where a runner is being
        // asked to trust a claim about deletion.
        //
        // Replaced with what is actually erased and actually sensitive: the
        // conversation carries injury notes and how somebody said they were
        // feeling, which is the most personal thing this app holds.
        const _DeletedItem(
          'Your conversations with the coach, and what it '
          'remembered about you',
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionLabel(
                'About your login',
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 8),
              Text(
                'Your login is your $kPlatformName profile, so Lift can use '
                'it too. If it holds no data from Lift we delete the profile '
                'as well. If it does, we delete everything this app holds '
                'and keep only the profile, so your data in Lift survives.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (_localData != null) ...<Widget>[
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  "Also erase this phone's copy",
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Switch(
                value: _erasePhone,
                onChanged: _busy
                    ? null
                    : (on) => setState(() => _erasePhone = on),
              ),
            ],
          ),
          Text(
            _erasePhone
                ? 'Your runs, plan, coach conversations, name and photo are '
                      'removed from this phone as well.'
                : 'Your runs stay on this phone, and nothing on it is backed '
                      'up any more.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (email != null) ...<Widget>[
          Text(
            'Signed in as $email',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text('Type $_phrase to confirm', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _confirm,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: _phrase),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.danger,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 24),
        DestructiveButton(
          label: 'Delete my data',
          busy: _busy,
          onPressed: _armed ? _delete : null,
        ),
        const SizedBox(height: 8),
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: <Widget>[
        const Icon(
          Icons.check_circle_outline,
          size: 40,
          color: AppColors.success,
        ),
        const SizedBox(height: 16),
        Text(
          // "Your data is deleted" over a phone still holding every run was
          // true of the server and false of the thing in the runner's hand.
          _phoneCopy == _PhoneCopy.kept || _phoneCopy == _PhoneCopy.eraseFailed
              ? 'Deleted from our servers'
              : 'Your data is deleted',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(_serverSentence(result), style: body),
        if (phone != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(phone, style: body),
        ],
        if (_stillBilling) ...<Widget>[
          const SizedBox(height: 20),
          _StillBilling(
            subscription: _subscription!,
            onManage: _manageSubscription,
          ),
        ],
        const SizedBox(height: 32),
        FilledButton(onPressed: _finish, child: const Text('Done')),
      ],
    );
  }

  /// What the server did, including the login -- which was said wrongly for
  /// two of the three answers the server can give.
  static String _serverSentence(AccountDeletionResult result) {
    const removed =
        'Every run, route point, split, and your runner profile have been '
        'removed from our servers';
    if (result.accountDeleted) return '$removed, along with your login.';
    if (result.loginRetainedForSiblingApp) {
      return '$removed. Your login is still active because Lift is using '
          'it — email hello@mgkcodes.com if you want that removed too.';
    }
    return '$removed. Your login could not be removed — email '
        'hello@mgkcodes.com and we will remove it.';
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = billingStoreFor(subscription, defaultTargetPlatform).label;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel(
            'About your subscription',
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 8),
          Text(
            'Deleting your account does not cancel your subscription. Cancel '
            'it in $store, or it will keep renewing.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          AppTextButton(label: 'Manage subscription', onPressed: onManage),
        ],
      ),
    );
  }
}

/// What became of this phone's copy of the training.
enum _PhoneCopy {
  /// No eraser to offer: the preview harness, and tests not about it.
  notMentioned,
  erased,
  kept,
  eraseFailed,
}

class _DeletedItem extends StatelessWidget {
  const _DeletedItem(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.remove, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
