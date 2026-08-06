import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../domain/backup_consent.dart';

/// Asks, once, whether the runner's data may leave the phone.
///
/// This exists because consent that has to be *found* is not really offered.
/// Backup defaults to off and restore does nothing without it, so without this
/// the promise "everything survives a lost phone" would hold only for someone
/// who happened to open Settings and scroll — which is the same as it not
/// holding.
///
/// Deliberately not dismissible by tapping outside. Both answers are fine and
/// either can be changed later, but a dialog that can be waved away leaves the
/// question unanswered, and unanswered behaves as no. A runner should decline
/// on purpose rather than by accident.
///
/// It is asked **after** sign-in and **before** the restore, because the answer
/// decides whether there is a restore at all.
Future<BackupConsent?> askBackupConsent(BuildContext context) =>
    showDialog<BackupConsent>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Keep a copy of your training?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                // Names what it covers rather than saying "your data". Someone
                // deciding whether to upload their injury notes and their
                // conversations with the coach is entitled to know that is the
                // decision they are making.
                'Your runs, routes, heart rate, your plan and what the coach '
                'remembers about you would be stored to your account, so you '
                'can pick up on a new phone.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 12),
              Text(
                'This is health information, so we only keep it if you say so. '
                'You can change your mind in Settings at any time, and turning '
                'it off deletes what has been stored.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  height: 1.45,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              // Says what it costs, so declining is a decision rather than a
              // dismissal. "Not now" would imply the question comes back.
              onPressed: () =>
                  Navigator.of(context).pop(BackupConsent.declined),
              child: const Text('Keep it on this phone only'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(BackupConsent.granted),
              child: const Text('Back it up'),
            ),
          ],
        );
      },
    );
