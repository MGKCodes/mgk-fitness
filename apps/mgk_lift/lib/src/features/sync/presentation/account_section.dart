import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/sync_status.dart';
import 'backup_messages.dart';
import 'backup_scheduler.dart';

/// The account card in Settings: who is signed in, what is waiting, when it
/// last went, what the server refused and why, and a way to send it now.
///
/// **It reports, it does not sell.** This was called Backup, and the copy under
/// it explained that an account would follow you to a new phone. Both were
/// wrong in the same way: an account is a thing people already understand, and
/// explaining that a cloud account is readable when you sign in reads as either
/// a sales pitch or an insult. It is just an account.
///
/// So every line here is a statement of state — signed in or not, what is
/// waiting, when it last ran — and none of them argue for anything. The one
/// fact worth stating unprompted is that training is on one device only,
/// because that is the state and discovering it after losing a phone is the
/// worst possible time.
///
/// **Manual here, automatic elsewhere.** Backup runs by itself at checkpoints
/// (see `BackupScheduler`); this is where somebody who wants it now can have
/// it now, and where each refusal is listed with its reason.
class AccountSection extends StatelessWidget {
  const AccountSection({
    super.key,
    required this.status,
    required this.isSignedIn,
    this.email,
    this.onSyncNow,
    this.onSignIn,
    this.now,
  });

  final BackupStatus status;
  final bool isSignedIn;

  /// Shown as the card's title when signed in, so the section names the account
  /// it is talking about rather than describing one in the abstract.
  final String? email;

  final VoidCallback? onSyncNow;
  final VoidCallback? onSignIn;

  /// What to measure "last checked" against. Null is the wall clock.
  ///
  /// Injected for the same reason [ProfileSurface] injects its clock: without
  /// it, a preview of a sync that happened three minutes ago reads "20d ago"
  /// and gets worse every day, because the fixture is pinned and the clock is
  /// not.
  final DateTime? now;

  bool get _syncing => status.state == BackupState.running;

  /// Signed in on this device, but the server no longer accepts it.
  bool get _expired => isSignedIn && status.state == BackupState.expired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = isSignedIn ? _problem() : null;

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
                if (_syncing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _status(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                height: 1.4,
              ),
            ),

            if (problem != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                // What it means, not what the server said. A PostgREST code is
                // not something to put in front of somebody, and it is not
                // their problem to fix.
                problem,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],

            // Each refusal, by name, with the reason. A refused workout waits
            // for an edit rather than being retried, so this is the one place
            // it is said in full.
            if (isSignedIn)
              for (final r in status.pending.rejected) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.error_outline,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        rejectionLine(r),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

            const SizedBox(height: AppSpacing.md),
            // Full width, like every other button in the app. Left-aligned in
            // a full-width card it read as an afterthought.
            SizedBox(
              width: double.infinity,
              child: !isSignedIn || _expired
                  ? AppOutlinedButton(
                      onPressed: onSignIn,
                      label: _expired ? 'Sign in again' : 'Sign in',
                      expand: true,
                    )
                  : AppOutlinedButton(
                      onPressed: _syncing ? null : onSyncNow,
                      // "Sync now" either way. The old second label said
                      // "check for changes", which understated it — the run
                      // pushes and pulls regardless, and may bring down what
                      // another device wrote.
                      label: 'Sync now',
                      expand: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The one line about what stopped the last run, or null when nothing did.
  String? _problem() => switch (status.state) {
    BackupState.offline =>
      'No connection. Your training is safe on this phone and goes up when '
          'you\'re back online.',
    BackupState.failed =>
      'Backup failed. Your training is safe on this phone, and it tries '
          'again shortly.',
    BackupState.unavailable =>
      'Backup isn\'t available right now. Your training is safe on this '
          'phone.',
    BackupState.expired => 'Sign in again to keep backing up.',
    _ => null,
  };

  String _status() {
    final pending = status.pending;
    final waiting = waitingPhrase(pending);
    if (!isSignedIn) {
      // The state, and nothing after it. The number makes it concrete where
      // there is one.
      if (waiting == null) return 'Your training is on this phone only.';
      final one = pending.workouts + pending.savedWorkouts == 1;
      return '$waiting ${one ? 'is' : 'are'} on this phone only.';
    }
    if (waiting != null) return '$waiting waiting to upload.';
    // What the last run actually moved. Without it the one moment the feature
    // visibly did something passes in silence.
    final report = status.lastReport;
    if (report != null && report.outcome == SyncOutcome.synced) {
      final parts = <String>[
        if (report.pushed > 0) '${report.pushed} up',
        if (report.pulled > 0) '${report.pulled} down',
      ];
      if (parts.isNotEmpty) {
        return 'Saved. ${parts.join(', ')} just now.';
      }
    }
    final last = pending.lastSyncedAt;
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
