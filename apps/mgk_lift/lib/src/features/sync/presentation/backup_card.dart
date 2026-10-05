import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/sync_status.dart';
import 'backup_messages.dart';
import 'backup_scheduler.dart';

/// Where backup stands, on the account screen: what is waiting, when it last
/// went, what the server refused and why, and a way to send it now.
///
/// **It reports, it does not sell.** This was called Backup once before, and
/// the copy under it explained that an account would follow you to a new
/// phone. Both were wrong in the same way: an account is a thing people already
/// understand, and explaining that a cloud account is readable when you sign in
/// reads as either a sales pitch or an insult.
///
/// So every line here is a statement of state — what is waiting, when it last
/// ran — and none of them argue for anything.
///
/// **Manual here, automatic elsewhere.** Backup runs by itself at checkpoints
/// (see `BackupScheduler`); this is where somebody who wants it now can have
/// it now, and where each refusal is listed with its reason.
///
/// **This was the card at the top of Settings**, with the account's address as
/// its head. Settings now leads with the suite's profile card, as Run's does,
/// and says where backup stands in one row ([backupRowValue]); the detail is
/// here, one tap in.
class BackupCard extends StatelessWidget {
  const BackupCard({
    super.key,
    required this.status,
    this.onSyncNow,
    this.onSignIn,
    this.now,
  });

  final BackupStatus status;

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
  bool get _expired => status.state == BackupState.expired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _problem();
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: 1.4,
    );
    final said = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
      height: 1.4,
    );

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(backupLine(status, now: now), style: quiet),
              ),
              if (_syncing) ...<Widget>[
                const SizedBox(width: AppSpacing.md),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),

          if (problem != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            // What it means, not what the server said. A PostgREST code is
            // not something to put in front of somebody, and it is not their
            // problem to fix.
            Text(problem, style: said),
          ],

          // Each refusal, by name, with the reason. A refused workout waits
          // for an edit rather than being retried, so this is the one place
          // it is said in full.
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
                Expanded(child: Text(rejectionLine(r), style: said)),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          _expired
              ? AppOutlinedButton(
                  onPressed: onSignIn,
                  label: 'Sign in again',
                  expand: true,
                )
              : AppOutlinedButton(
                  onPressed: _syncing ? null : onSyncNow,
                  // "Sync now" rather than "Back up now". The run pushes and
                  // pulls regardless, and may bring down what another device
                  // wrote.
                  label: 'Sync now',
                  expand: true,
                ),
        ],
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
}

/// What exists in one place only, for somebody with no account: the note on
/// Settings' profile card.
///
/// The state, and nothing after it. The number makes it concrete where there
/// is one. It is the one fact worth stating unprompted, because discovering it
/// after losing a phone is the worst possible time.
String phoneOnlyLine(SyncPending pending) {
  final waiting = waitingPhrase(pending);
  if (waiting == null) return 'Your training is on this phone only.';
  final one = pending.workouts + pending.savedWorkouts == 1;
  return '$waiting ${one ? 'is' : 'are'} on this phone only.';
}

/// Where backup stands for somebody signed in, as a sentence.
String backupLine(BackupStatus status, {DateTime? now}) {
  final pending = status.pending;
  final waiting = waitingPhrase(pending);
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

/// Where backup stands, short enough to be a row's value on the settings
/// index, and whether it needs the lifter: only what they alone can put right
/// is coloured, a lapsed sign-in and a workout the server refused.
(String, bool) backupRowValue(BackupStatus status) {
  final pending = status.pending;
  if (status.state == BackupState.expired) return ('Sign in again', true);
  if (pending.rejected.isNotEmpty) {
    final n = pending.rejected.length;
    return ('$n need${n == 1 ? 's' : ''} attention', true);
  }
  return switch (status.state) {
    BackupState.running => ('Backing up', false),
    BackupState.offline => ('Offline', false),
    BackupState.failed => ('Failed, retrying', false),
    BackupState.unavailable => ('Unavailable', false),
    _ when pending.hasWork => (
      '${pending.workouts + pending.savedWorkouts} waiting',
      false,
    ),
    _ when pending.lastSyncedAt == null => ('Nothing saved yet', false),
    _ => ('Up to date', false),
  };
}

/// Rough, and deliberately so. "3 minutes ago" is the answer to "did that
/// work"; a timestamp to the second is not.
String _ago(DateTime at, DateTime? now) {
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
