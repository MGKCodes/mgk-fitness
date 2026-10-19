import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../auth/domain/account.dart';
import '../../legal/domain/account_deleter.dart';
import '../../legal/presentation/delete_account_screen.dart';
import '../../sync/presentation/backup_card.dart';
import '../../sync/presentation/backup_scheduler.dart';
import 'account_name_sheet.dart';

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
/// **Headed by the account's name, when it has one** (Run's ADR-0047): the
/// MGKFitness account's name, the one Run shows too, with the address under
/// it and its initials in the circle. Lift keeps no photograph of anybody
/// (O1). With no name the address stands in its place and the circle holds
/// its first letter, as it did until 2.0.1.
///
/// **The name is given or changed here**, on the *Name* row, which nothing
/// prompts towards: it is how an Apple account, which is never asked, or
/// somebody who skipped the question, gives one. Lift's coach does not use
/// it.
class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.email,
    this.name,
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

  /// The account's name when the screen opened, or null for none. Changed
  /// here, the screen shows the new one at once.
  final String? name;

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
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late String? _name = widget.name;

  /// *Name*: the sheet, and afterwards whatever the account now says, which
  /// is what Run will show too.
  Future<void> _rename(AuthService auth) async {
    final saved = await showAccountNameSheet(
      context,
      current: _name,
      save: auth.updateName,
    );
    if (saved != true || !mounted) return;
    setState(() => _name = auth.current?.name);
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.email;
    final backup = widget.backup;
    final planLabel = widget.planLabel;
    final onSignOut = widget.onSignOut;
    final onManageSubscription = widget.onManageSubscription;
    final onRestorePurchases = widget.onRestorePurchases;
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: 1.4,
    );
    Widget card(BackupStatus status) => BackupCard(
      status: status,
      onSyncNow: widget.onSyncNow,
      onSignIn: widget.onSignIn,
      now: widget.now,
    );
    final service = widget.auth;
    final delete = widget.deleter;
    final address = email?.trim() ?? '';
    final name = _name;

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
                    initials: name != null
                        ? initialsFor(name)
                        : address.isEmpty
                        ? null
                        : address.characters.first.toUpperCase(),
                    size: 96,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    name ?? (address.isEmpty ? 'Signed in' : address),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  // The address under a name, as confirmation: it is still
                  // what somebody signed in as the wrong account notices.
                  if (name != null && address.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(address, style: dim, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),

            // Shown with nothing in it only where it can be changed: a build
            // with no server has no account to name.
            if (service != null || name != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              SettingsGroup(
                label: 'Profile',
                children: <Widget>[
                  SettingsRow(
                    title: 'Name',
                    value: name ?? 'Not set',
                    onTap: service == null ? null : () => _rename(service),
                  ),
                ],
              ),
            ],

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
                      onTap: () => onRestorePurchases(),
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
                  onSignOut();
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
                      onAccountGone: widget.onAccountGone,
                      eraseThisPhone: widget.eraseThisPhone,
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
