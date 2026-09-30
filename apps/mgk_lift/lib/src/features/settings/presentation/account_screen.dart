import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../auth/domain/account.dart';
import '../../legal/domain/account_deleter.dart';
import '../../legal/presentation/delete_account_screen.dart';
import '../../sync/presentation/account_section.dart';
import '../../sync/presentation/backup_scheduler.dart';

/// Everything about the account, one tap behind the card at the top of
/// Settings (19): where backup stands, the subscription and its restore, and
/// the two ways out — signing out, and deleting.
///
/// Run's Settings has the same shape. The index shows who is signed in and
/// what they pay for; the things somebody does to their account, which are
/// rare and some of them for good, are a screen further in rather than rows
/// on the page opened most.
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
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    Widget section(BackupStatus status) => AccountSection(
      status: status,
      isSignedIn: true,
      email: email,
      planLabel: planLabel,
      onSyncNow: onSyncNow,
      onSignIn: onSignIn,
      now: now,
    );
    final service = auth;
    final delete = deleter;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: <Widget>[
            if (backup case final backup?)
              ValueListenableBuilder<BackupStatus>(
                valueListenable: backup,
                builder: (context, status, _) => section(status),
              )
            else
              section(const BackupStatus()),
            const SizedBox(height: AppSpacing.md),
            if (planLabel != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: SettingsGroup(
                  label: 'Subscription',
                  children: <Widget>[
                    SettingsRow(title: 'Plan', value: planLabel),
                    if (onRestorePurchases != null)
                      SettingsRow(
                        title: 'Restore purchases',
                        onTap: () => onRestorePurchases!(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SettingsGroup(
                label: 'Leaving',
                children: <Widget>[
                  if (onSignOut != null)
                    SettingsRow(
                      title: 'Sign out',
                      // Says what survives, because the fear this row
                      // triggers is that signing out is a way to lose
                      // something.
                      value: 'Training stays on this phone',
                      onTap: () {
                        Navigator.of(context).pop();
                        onSignOut!();
                      },
                    ),
                  if (service != null && delete != null)
                    SettingsRow(
                      title: 'Delete account',
                      tint: AppColors.danger,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DeleteAccountScreen(
                            auth: service,
                            deleter: delete,
                            onAccountGone: onAccountGone,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
