import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../domain/backup_consent.dart';

/// The backup switch, and the only place a runner is asked for the consent that
/// everything leaving the device depends on.
///
/// Worded as a choice about **their data**, not about a feature. "Back up my
/// data" is a thing the runner is deciding to allow; "Enable cloud sync" is a
/// product setting they are being sold. Under UK GDPR the first is what consent
/// to processing special-category data has to look like: specific, informed,
/// and as easy to withdraw as it was to give.
class BackupSection extends StatelessWidget {
  const BackupSection({
    super.key,
    required this.consent,
    required this.onChanged,
    this.busy = false,
  });

  final BackupConsent consent;

  /// Called with the new answer. Granting starts the mirror; withdrawing stops
  /// it and offers to remove what is already stored.
  final ValueChanged<BackupConsent> onChanged;

  /// True while a withdrawal is being carried out, so the switch cannot be
  /// flipped again mid-delete.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xs,
          ),
          child: SectionLabel('Your data'),
        ),
        SwitchListTile(
          value: consent.allowsBackup,
          onChanged: busy
              ? null
              : (on) => onChanged(
                  on ? BackupConsent.granted : BackupConsent.declined,
                ),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          title: const Text('Back up my data'),
          subtitle: Text(
            _subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.4,
            ),
          ),
          isThreeLine: true,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: Text(
            // Named plainly. A runner deciding whether to upload their injury
            // notes and their conversations with the coach is entitled to know
            // that is what the switch covers, rather than "your activity".
            'Runs, routes, heart rate, your plan and what the coach remembers '
            'about you. This is health information, so it is only sent if you '
            'say so, and turning it off deletes what has already been stored.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  String get _subtitle => switch (consent) {
    // The unanswered state says what happens NOW, not what the switch does.
    // "Off" would imply a decision the runner has not made.
    BackupConsent.unknown =>
      'Not set up. Everything stays on this phone, and a lost phone loses it.',
    BackupConsent.granted =>
      'On. You can sign in on a new phone and pick up where you left off.',
    BackupConsent.declined =>
      'Off. This phone is the only copy — an uninstall loses everything.',
  };
}
