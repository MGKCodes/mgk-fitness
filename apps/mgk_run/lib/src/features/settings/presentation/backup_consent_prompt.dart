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
            // Says what it costs, so declining is a decision rather than a
            // dismissal. "Not now" would imply the question comes back.
            AppTextButton(
              label: 'Keep it on this phone only',
              onPressed: () =>
                  Navigator.of(context).pop(BackupConsent.declined),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(BackupConsent.granted),
              child: const Text('Back it up'),
            ),
          ],
        );
      },
    );

/// The same question, asked of somebody who has no account yet — once they have
/// something worth keeping.
///
/// **Why this is a second door rather than the one above.** [askBackupConsent]
/// is asked at launch, before the restore, because for a returning runner the
/// answer decides whether there is a restore at all. A new runner has no such
/// moment: the app now opens on a working tracker with nothing signed in, and
/// asking them at launch would be asking permission to store data that does not
/// exist yet, ninety seconds after install, from somebody who has not seen the
/// app do anything (ADR-0012). So they are asked here instead — after [runs]
/// recorded runs, when the phone holds a training log they would actually mind
/// losing.
///
/// **It is the consent, not a lead-in to it.** Answering yes raises sign-up,
/// because the mirror needs an account to attribute rows to, and it would be
/// easy to treat this dialog as a teaser and ask the real question afterwards.
/// That would be two dialogs for one decision, and the second would be asked of
/// somebody who had already said yes. So this names exactly what is covered, in
/// the same words the switch in Settings uses, and the account that follows is
/// the mechanism rather than a further question.
///
/// Both answers are decisions. "Not now" is deliberately not offered: this is
/// the only time it is asked, and an answer that implies the question comes
/// back would be a lie. Declining is recorded as a decline, which is what stops
/// it being raised again — and it is one switch away in Settings forever after.
Future<BackupConsent?> askKeepRunsSafe(
  BuildContext context, {
  required int runs,
}) => showDialog<BackupConsent>(
  context: context,
  barrierDismissible: false,
  builder: (context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Keep these safe?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            // Their own number, not "some runs". The whole reason to ask now
            // rather than at launch is that there is something real on the
            // phone, and saying how much is what makes that concrete.
            "You've recorded $runs runs, and they are on this phone only. "
            'Lose the phone and they go with it.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 12),
          Text(
            // The same enumeration the switch in Settings gives, deliberately
            // word for word: a runner deciding this is entitled to know it
            // covers their injury notes and what they told the coach, not just
            // "their activity".
            'Backing up stores your runs, routes, heart rate, your plan and '
            'what the coach remembers about you to an account, so you can pick '
            'up on a new phone. This is health information, so we only keep it '
            'if you say so, and turning it off deletes what has been stored.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            // Said plainly and up front. Finding out only after tapping that
            // the answer costs an email address is how a reasonable ask starts
            // to feel like a trick.
            'You will need an account, which takes a moment.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.45,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        AppTextButton(
          label: 'Keep them on this phone only',
          onPressed: () => Navigator.of(context).pop(BackupConsent.declined),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(BackupConsent.granted),
          child: const Text('Back them up'),
        ),
      ],
    );
  },
);
