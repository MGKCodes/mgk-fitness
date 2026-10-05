import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../auth/domain/account.dart';
import '../../legal/domain/account_deleter.dart';
import '../../legal/presentation/delete_account_screen.dart';
import '../../sync/presentation/backup_card.dart';
import '../../sync/presentation/backup_scheduler.dart';

/// The account, as a profile: who it is, where its backup stands, what it is
/// paying for, and the two ways out of it.
///
/// One tap behind the card at the top of Settings (19), and laid out as Run's
/// account screen is, because it is the same account: the person centred at
/// the top, then groups, then the ways out as buttons at the foot with a line
/// under each saying what it does. The index shows who is signed in and what
/// they pay for; the things somebody does to their account, which are rare and
/// some of them for good, are a screen further in rather than rows on the page
/// opened most.
///
/// Lift keeps no photograph of anybody (O1) and asks no name, so the circle
/// holds the address's first letter and the address stands where Run's has a
/// name.
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.email,
    this.backup,
    this.planLabel,
    this.onSyncNow,
    this.onSignIn,
    this.onRestorePurchases,
    this.onSignOut,
    this.auth,
    this.deleter,
    this.onAccountGone,
    this.eraseThisPhone,
    this.onManageSubscription,
    this.now,
  });

  final String? email;
  final ValueListenable<BackupStatus>? backup;

  /// `Subscribed`, `Free`, or null when this build sells nothing.
  final String? planLabel;

  final VoidCallback? onSyncNow;
  final VoidCallback? onSignIn;
  final Future<void> Function()? onRestorePurchases;
  final VoidCallback? onSignOut;
  final AuthService? auth;
  final AccountDeleter? deleter;
  final Future<void> Function()? onAccountGone;

  /// See [DeleteAccountScreen.eraseThisPhone].
  final Future<void> Function()? eraseThisPhone;

  /// The store's page for the subscription, where it is managed and
  /// cancelled. Null hides the row: somebody not subscribed has nothing there
  /// to manage. Google Play's policy wants this way out inside the app.
  final VoidCallback? onManageSubscription;

  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: 1.4,
    );
    Widget card(BackupStatus status) => BackupCard(
      status: status,
      onSyncNow: onSyncNow,
      onSignIn: onSignIn,
      now: now,
    );
    final service = auth;
    final delete = deleter;
    final address = email?.trim() ?? '';

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
            // Centred rather than in a row: this is the one screen where the
            // person is the subject.
            Center(
              child: Column(
                children: <Widget>[
                  InitialsAvatar(
                    initials: address.isEmpty
                        ? null
                        : address.characters.first.toUpperCase(),
                    size: 96,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    address.isEmpty ? 'Signed in' : address,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: SectionLabel('Backup'),
            ),
            // Live, so a run started here is reported as it happens.
            if (backup case final backup?)
              ValueListenableBuilder<BackupStatus>(
                valueListenable: backup,
                builder: (context, status, _) => card(status),
              )
            else
              card(const BackupStatus()),

            if (planLabel != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              SettingsGroup(
                label: 'Coaching',
                children: <Widget>[
                  SettingsRow(title: 'Plan', value: planLabel),
                  if (onManageSubscription != null)
                    SettingsRow(
                      title: 'Manage subscription',
                      onTap: onManageSubscription,
                    ),
                  if (onRestorePurchases != null)
                    SettingsRow(
                      title: 'Restore purchases',
                      onTap: () => onRestorePurchases!(),
                    ),
                ],
              ),
            ],

            const SizedBox(height: AppSpacing.xxl),
            if (onSignOut != null) ...<Widget>[
              AppOutlinedButton(
                label: 'Sign out',
                expand: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  onSignOut!();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              // Says what survives, because the fear this button triggers is
              // that signing out is a way to lose something.
              Text('Your training stays on this phone.', style: dim),
            ],
            if (service != null && delete != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              DestructiveButton(
                label: 'Delete account',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DeleteAccountScreen(
                      auth: service,
                      deleter: delete,
                      onAccountGone: onAccountGone,
                      eraseThisPhone: eraseThisPhone,
                      onManageSubscription: onManageSubscription,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This app only, or your whole account. It cannot be undone.',
                style: dim,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
