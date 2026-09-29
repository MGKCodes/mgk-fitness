import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../auth/data/auth_repository.dart';
import '../../coaching/domain/coach_subscription.dart';
import '../../coaching/presentation/purchase_screen.dart' show storeName;
import '../../legal/domain/account_deleter.dart';
import '../../legal/presentation/delete_account_screen.dart';
import 'avatar.dart';
import 'settings_row.dart';

/// The account, as a profile: a face, a name, what it is paying for, and the
/// two ways out of it.
///
/// ## Why the ways out are behind a tap
///
/// They were buttons on the settings index, which put **Sign out** and **Delete
/// account** — the two things on the whole screen a person could regret — in
/// permanent view of somebody who opened Settings to change their units. It
/// also produced a second Delete account button, because one already exists
/// inside Privacy & legal where the law expects to find it.
///
/// ## Why it is called Account rather than Profile
///
/// The app already has a **Profile tab**, and that one is about running —
/// lifetime totals, records, the log. Naming this screen Profile too would give
/// the app two of them meaning different things. It looks like a profile, which
/// is what somebody arriving here expects to see; it is named for what it holds.
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.auth,
    required this.deleter,
    required this.subscription,
    required this.memberSince,
    required this.name,
    required this.photo,
    required this.onSignOut,
    required this.onEditName,
    required this.onPickPhoto,
    required this.onRemovePhoto,
    required this.onCreateAccount,
  });

  final AuthRepository auth;
  final AccountDeleter deleter;

  /// Null while the entitlement read is still in flight.
  final CoachSubscription? subscription;

  final DateTime? memberSince;
  final String? name;
  final File? photo;

  /// Runs the confirmation and the sign-out itself. Owned by the settings
  /// screen because signing out has to drop the whole pushed stack.
  final Future<void> Function() onSignOut;

  final Future<void> Function() onEditName;
  final Future<void> Function() onPickPhoto;

  /// Null when there is no photo to remove, which is what hides the row.
  final Future<void> Function()? onRemovePhoto;

  /// Raises sign-up. Reached only when there is no account yet.
  final VoidCallback onCreateAccount;

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
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            // The face, big, and tappable to change. Centred rather than in a
            // row: this is the one screen where the person IS the subject, and
            // a 96px avatar pinned left with text beside it reads as a list
            // item about somebody rather than a page belonging to them.
            Center(
              child: Column(
                children: <Widget>[
                  Avatar(
                    photo: photo,
                    name: name,
                    size: 96,
                    onTap: () => unawaited(onPickPhoto()),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    name ?? 'No name',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      // A name that was never given is absence, not a value.
                      color: name == null
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppTextButton(
                    label: photo == null ? 'Add a photo' : 'Change photo',
                    onPressed: () => unawaited(onPickPhoto()),
                  ),
                  if (onRemovePhoto != null)
                    AppTextButton(
                      label: 'Remove photo',
                      onPressed: () => unawaited(onRemovePhoto!()),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              // Said once, here, where the photo is chosen. It is the only
              // claim on this screen somebody might not assume. Not "not
              // included in backup": nothing excludes it from the phone's own.
              'Your photo stays with you. It is never uploaded to us and never '
              "sent to your coach, though your phone's own backup may include "
              'it.',
              style: dim,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.xl),
            SettingsGroup(
              label: 'Details',
              children: <Widget>[
                SettingsRow(
                  title: 'Coach calls you',
                  value: name ?? 'Nothing in particular',
                  onTap: () => unawaited(onEditName()),
                ),
                if (email != null) SettingsRow(title: 'Email', value: email),
                if (memberSince != null)
                  SettingsRow(
                    title: 'Running since',
                    value: _monthYear(memberSince!),
                  ),
              ],
            ),

            if (subscription != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              _SubscriptionBlock(subscription!),
            ],

            const SizedBox(height: AppSpacing.xxl),

            // **The ways out need an account to be ways out of.** Signed out,
            // offering to sign out of nothing and delete what was never made
            // is two controls that can only fail -- so the invitation takes
            // their place.
            //
            // The screen itself stays reachable signed out, which it briefly
            // was not: the name and the photo are PROFILE, and both exist
            // before an account does. The intro gathers a name with no
            // account, ADR-0019 expects it to be correctable, and gating this
            // screen on a session quietly took away the only place to do it.
            if (email == null) ...<Widget>[
              PrimaryButton(
                label: 'Create an account',
                onPressed: onCreateAccount,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Backs up your training, and lets you ask for a plan. Your '
                'name and photo are already yours either way.',
                style: dim,
              ),
            ] else ...<Widget>[
              OutlinedButton(
                onPressed: () => unawaited(onSignOut()),
                child: const Text('Sign out'),
              ),
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

    final (String status, bool bad) = switch (subscription.standing) {
      SubscriptionStanding.none => ('Not subscribed', false),
      SubscriptionStanding.active => ('Active', false),
      SubscriptionStanding.billingRetry => ('Payment failed', true),
      SubscriptionStanding.ended => ('Ended', false),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsGroup(
          label: 'Coaching',
          children: <Widget>[
            SettingsRow(title: 'Plan', value: subscription.tier.label),
            SettingsRow(
              title: 'Status',
              value: status,
              tint: bad ? AppColors.danger : null,
            ),
          ],
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
