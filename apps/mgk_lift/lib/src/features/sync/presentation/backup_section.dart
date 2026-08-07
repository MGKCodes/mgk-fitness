import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/sync_status.dart';

/// The backup row in Settings: what is waiting, when it last went, and a way to
/// send it now.
///
/// **Manual, and honest about being a backup.** Nothing here is on the path of
/// logging a set — the local database already has it. So this reports rather
/// than reassures: a lifter who has not signed in is told plainly that their
/// training is on one device only, because that is the fact and discovering it
/// after losing a phone is the worst possible time.
class BackupSection extends StatelessWidget {
  const BackupSection({
    super.key,
    required this.pending,
    required this.isSignedIn,
    this.isSyncing = false,
    this.lastReport,
    this.onSyncNow,
    this.onSignIn,
  });

  final SyncPending? pending;
  final bool isSignedIn;
  final bool isSyncing;
  final SyncReport? lastReport;
  final VoidCallback? onSyncNow;
  final VoidCallback? onSignIn;

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
                  isSignedIn
                      ? Icons.cloud_outlined
                      : Icons.cloud_off_outlined,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    isSignedIn ? 'Backup' : 'This device only',
                    style: theme.textTheme.titleSmall,
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
                // not something to put in front of somebody who was trying to
                // back up their training — and it is not their problem to fix.
                'Could not reach the server. Your training is safe on this '
                'device and will go up next time.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            if (!isSignedIn)
              OutlinedButton(
                onPressed: onSignIn,
                child: const Text('Sign in to back up'),
              )
            else
              OutlinedButton(
                onPressed: isSyncing ? null : onSyncNow,
                child: Text(count > 0 ? 'Back up now' : 'Check for changes'),
              ),
          ],
        ),
      ),
    );
  }

  String _status(int count) {
    if (!isSignedIn) {
      return count == 0
          ? 'Your training is only on this phone. Sign in and it is backed up '
                'and follows you to a new one.'
          // The number makes it concrete. "Sign in to back up" is easy to
          // ignore; "9 sessions exist nowhere else" is not.
          : '$count session${count == 1 ? '' : 's'} ${count == 1 ? 'exists' : 'exist'} '
                'nowhere else. Sign in and they are backed up.';
    }
    if (count > 0) {
      return '$count session${count == 1 ? '' : 's'} waiting to upload.';
    }
    final last = pending?.lastSyncedAt;
    return last == null
        ? 'Nothing has been backed up yet.'
        : 'Everything is backed up. Last checked ${_ago(last)}.';
  }

  /// Rough, and deliberately so. "3 minutes ago" is the answer to "did that
  /// work"; a timestamp to the second is not.
  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
