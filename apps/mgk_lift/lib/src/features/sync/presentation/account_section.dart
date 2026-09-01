import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/sync_status.dart';

/// The account card in Settings: who is signed in, what is waiting, when it
/// last went, and a way to send it now.
///
/// **This used to be called Backup, and calling it that was the mistake.**
/// Backup names a failure mode — insurance against losing a phone — which makes
/// the account sound like a precaution somebody might reasonably skip. It is
/// not. It is where training lives across devices, what the coach's memory
/// hangs off, what Run shares, and what a subscription attaches to. A lost
/// phone is a case it *handles*, not the thing it *is*.
///
/// So the card leads with the account and lets the lost-phone case be the fine
/// print it deserves to be. The one place "saved" survives is the status line,
/// where it is reporting what the last run actually moved rather than making a
/// pitch.
///
/// **Manual, and honest about it.** Nothing here is on the path of logging a
/// set — the local database already has it. So this reports rather than
/// reassures: somebody who has not signed in is told plainly that their
/// training is on one device only, because that is the fact and discovering it
/// after losing a phone is the worst possible time.
class AccountSection extends StatelessWidget {
  const AccountSection({
    super.key,
    required this.pending,
    required this.isSignedIn,
    this.email,
    this.isSyncing = false,
    this.lastReport,
    this.onSyncNow,
    this.onSignIn,
    this.now,
  });

  final SyncPending? pending;
  final bool isSignedIn;

  /// Shown as the card's title when signed in, so the section names the account
  /// it is talking about rather than describing one in the abstract.
  final String? email;

  final bool isSyncing;
  final SyncReport? lastReport;
  final VoidCallback? onSyncNow;
  final VoidCallback? onSignIn;

  /// What to measure "last checked" against. Null is the wall clock.
  ///
  /// Injected for the same reason [ProfileSurface] injects its clock: without
  /// it, a preview of a sync that happened three minutes ago reads "20d ago"
  /// and gets worse every day, because the fixture is pinned and the clock is
  /// not.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = pending?.workouts ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isSignedIn ? Icons.cloud_outlined : Icons.cloud_off_outlined,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    // The address, when there is one. An account is a specific
                    // thing belonging to a specific person, and naming it is
                    // also how somebody signed in as the wrong address finds
                    // out before they wonder where their training went.
                    isSignedIn ? (email ?? 'Signed in') : 'Not signed in',
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSyncing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _status(count),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                height: 1.4,
              ),
            ),

            if (lastReport?.isFailure ?? false) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                // What it means, not what the server said. A PostgREST code is
                // not something to put in front of somebody, and it is not
                // their problem to fix.
                'Could not reach the server. Your training is safe on this '
                'phone and will go up next time.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            // Full width, like every other button in the app. Left-aligned in
            // a full-width card it read as an afterthought.
            SizedBox(
              width: double.infinity,
              child: !isSignedIn
                  ? OutlinedButton(
                      onPressed: onSignIn,
                      child: const Text('Sign in'),
                    )
                  : OutlinedButton(
                      onPressed: isSyncing ? null : onSyncNow,
                      // "Sync now" either way. The old second label said
                      // "check for changes", which understated it — the run
                      // pushes and pulls regardless, and may bring down what
                      // another device wrote.
                      child: const Text('Sync now'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _status(int count) {
    if (!isSignedIn) {
      return count == 0
          ? 'Your training is on this phone only. An $kPlatformName account '
                'keeps it with you — on a new phone, and in '
                '$kPlatformName: Run.'
          // The number makes it concrete. A general invitation is easy to
          // ignore; "9 sessions exist nowhere else" is not.
          : '$count session${count == 1 ? '' : 's'} ${count == 1 ? 'exists' : 'exist'} '
                'nowhere else. An $kPlatformName account keeps '
                '${count == 1 ? 'it' : 'them'}.';
    }
    if (count > 0) {
      return '$count session${count == 1 ? '' : 's'} waiting to upload.';
    }
    // What the last run actually moved. Without it the one moment the feature
    // visibly did something passes in silence.
    final report = lastReport;
    if (report != null && report.outcome == SyncOutcome.synced) {
      final parts = <String>[
        if (report.pushed > 0) '${report.pushed} up',
        if (report.pulled > 0) '${report.pulled} down',
      ];
      if (parts.isNotEmpty) {
        return 'Saved. ${parts.join(', ')} just now.';
      }
    }
    final last = pending?.lastSyncedAt;
    return last == null
        ? 'Nothing saved yet.'
        : 'Everything is saved. Last checked ${_ago(last, now)}.';
  }

  /// Rough, and deliberately so. "3 minutes ago" is the answer to "did that
  /// work"; a timestamp to the second is not.
  static String _ago(DateTime at, DateTime? now) {
    final d = (now ?? DateTime.now()).difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
