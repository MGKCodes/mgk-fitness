import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../auth/data/auth_repository.dart';
import '../../coaching/domain/coach_subscription.dart';
import '../../coaching/presentation/purchase_screen.dart' show storeName;
import '../../legal/domain/account_deleter.dart';
import '../../legal/presentation/delete_account_screen.dart';
import 'settings_row.dart';

/// The account: who it is, what it is paying for, and the two ways out of it.
///
/// ## Why the ways out are behind a tap
///
/// They were buttons on the settings index, under the two groups. That put
/// **Sign out** and **Delete account** — the two things on the whole screen a
/// person could regret — in permanent view of somebody who opened Settings to
/// change their units. And it produced a second Delete account button, because
/// one already existed inside Privacy & legal where the law expects to find it.
///
/// A tap is the right amount of friction for both. Neither is something anybody
/// arrives at Settings intending to do by accident, and an account screen is
/// where a person looks for them.
///
/// ## And why it says more than the card did
///
/// The card on the index has room for an address and one line about the plan.
/// That is the right amount for an index and not enough to answer "what am I
/// actually paying for, and where do I cancel it?" — which, until 2026-09-11,
/// the app could not answer anywhere at all.
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.auth,
    required this.deleter,
    required this.subscription,
    required this.memberSince,
    required this.onSignOut,
  });

  final AuthRepository auth;
  final AccountDeleter deleter;

  /// Null while the entitlement read is still in flight.
  final CoachSubscription? subscription;

  final DateTime? memberSince;

  /// Runs the confirmation and the sign-out itself. Owned by the settings
  /// screen because signing out has to drop the whole pushed stack — see the
  /// note on `_signOut` there.
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = auth.currentEmail;
    final dim = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: 1.4,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: <Widget>[
                  if (email != null)
                    SettingsRow(title: 'Signed in as', value: email),
                  if (memberSince != null)
                    SettingsRow(
                      title: 'Running since',
                      value: _monthYear(memberSince!),
                    ),
                ],
              ),
            ),

            if (subscription != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              _SubscriptionBlock(subscription!),
            ],

            const SizedBox(height: AppSpacing.xxl),

            OutlinedButton(onPressed: onSignOut, child: const Text('Sign out')),
            const SizedBox(height: AppSpacing.sm),
            Text('Your runs stay on this device.', style: dim),

            const SizedBox(height: AppSpacing.xl),
            DestructiveButton(
              label: 'Delete account',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      DeleteAccountScreen(auth: auth, deleter: deleter),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Permanently removes your runs, profile, plans and coach '
              'conversations. It cannot be undone.',
              style: dim,
            ),
          ],
        ),
      ),
    );
  }
}

/// What the subscription is, in the detail an index cannot carry.
class _SubscriptionBlock extends StatelessWidget {
  const _SubscriptionBlock(this.subscription);

  final CoachSubscription subscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = storeName(defaultTargetPlatform);
    final dim = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: 1.4,
    );

    final (String status, Color colour) = switch (subscription.standing) {
      SubscriptionStanding.none => ('Not subscribed', AppColors.textTertiary),
      SubscriptionStanding.active => ('Active', AppColors.textTertiary),
      SubscriptionStanding.billingRetry => ('Payment failed', AppColors.danger),
      SubscriptionStanding.ended => ('Ended', AppColors.textTertiary),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: SectionLabel('Coaching'),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: <Widget>[
              SettingsRow(title: 'Plan', value: subscription.tier.label),
              SettingsRow(
                title: 'Status',
                value: status,
                tint: colour == AppColors.danger ? colour : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(_explanation(store), style: dim),
        ),
      ],
    );
  }

  /// The sentence the index has no room for: what this state means, and what
  /// to do about it if anything.
  String _explanation(String store) => switch (subscription.standing) {
    // Says what the free app *is* rather than what it lacks: recording is the
    // product, not a trial of one (ADR-0030).
    SubscriptionStanding.none =>
      'Recording your runs, your history and your pace are free and always '
          'will be. The coach — a plan, and its reading of your training — is '
          'the subscription.',
    SubscriptionStanding.active =>
      'Renews monthly. Cancel or change it in $store; we cannot do either from '
          'here, because $store takes the payment.',
    // The one worth explaining properly. The coach is locked and the runner
    // has cancelled nothing, so this has to carry both facts or it reads as
    // the app having lost their subscription.
    SubscriptionStanding.billingRetry =>
      'Your last payment did not go through. $store is retrying it, and the '
          'coach stays locked until it succeeds. Updating your payment method '
          'in $store is the fix — there is nothing to do here.',
    SubscriptionStanding.ended =>
      'Your subscription has ended and you are not being charged. Everything '
          'you recorded is still yours.',
  };
}

const List<String> _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthYear(DateTime at) => '${_months[at.month - 1]} ${at.year}';
