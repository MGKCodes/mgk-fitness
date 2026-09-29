import 'package:meta/meta.dart';

import '../domain/sync_status.dart';
import 'backup_scheduler.dart';

/// What a backup message offers to do about itself.
enum BackupAction {
  /// Nothing — it clears on its own, or there is nothing to do.
  none,

  /// Try now rather than at the next retry.
  retry,

  /// Sign in (again).
  signIn,

  /// Look at what needs attention — Settings, which lists each refusal.
  review,
}

@immutable
class BackupMessage {
  const BackupMessage(this.text, {this.action = BackupAction.none});

  final String text;
  final BackupAction action;

  @override
  bool operator ==(Object other) =>
      other is BackupMessage && other.text == text && other.action == action;

  @override
  int get hashCode => Object.hash(text, action);

  @override
  String toString() => 'BackupMessage($text, ${action.name})';
}

/// The line under a finished session on its summary.
///
/// **"Saved on this phone" first, always** — it is true the instant Finish is
/// tapped, and it is the thing somebody needs to hear standing in a basement.
/// Then what backup has made of it. *Backed up* only once a run has finished
/// since the session did, and the session is not waiting: before the first
/// read of the queue, "nothing waiting" means "not read yet", not "sent".
///
/// Signed out, it says the first half and stops. The account card's rule
/// holds here too: state the fact, do not sell the account.
BackupMessage sessionBackupMessage(
  BackupStatus status, {
  required String sessionId,
  required DateTime finishedAt,
}) {
  for (final r in status.pending.rejected) {
    if (r.id == sessionId) {
      return BackupMessage(
        'Saved on this phone, but it couldn\'t be backed up: '
        '${rejectionReason(r.detail)}.',
      );
    }
  }
  final ranSince = status.pending.lastSyncedAt?.isAfter(finishedAt) ?? false;
  if (status.state == BackupState.idle &&
      ranSince &&
      status.isBackedUp(sessionId)) {
    return const BackupMessage('Backed up.');
  }
  return switch (status.state) {
    BackupState.running => const BackupMessage(
      'Saved on this phone. Backing up…',
    ),
    BackupState.offline => const BackupMessage(
      'Saved on this phone. It\'ll back up when you\'re online.',
    ),
    BackupState.failed => const BackupMessage(
      'Saved on this phone. Backup failed, trying again shortly.',
      action: BackupAction.retry,
    ),
    BackupState.unavailable => const BackupMessage(
      'Saved on this phone. Backup isn\'t available right now.',
    ),
    BackupState.expired => const BackupMessage(
      'Saved on this phone. Sign in again to keep backing up.',
      action: BackupAction.signIn,
    ),
    BackupState.signedOut ||
    BackupState.idle => const BackupMessage('Saved on this phone.'),
  };
}

/// Track's pill — **only when something needs the lifter**, null otherwise.
///
/// Nothing when all is well, nothing while a run is under way, and nothing
/// for somebody who has never signed in: Track is the screen opened most, and
/// a permanent line about an account they chose not to make is nagging.
BackupMessage? trackBackupMessage(BackupStatus status) {
  final rejected = status.pending.rejected;
  if (rejected.isNotEmpty) {
    return BackupMessage(
      rejected.length == 1
          ? '"${rejected.single.name}" couldn\'t be backed up'
          : '${rejected.length} workouts couldn\'t be backed up',
      action: BackupAction.review,
    );
  }
  final waiting = waitingPhrase(status.pending);
  return switch (status.state) {
    BackupState.expired => const BackupMessage(
      'Sign in again to keep backing up',
      action: BackupAction.signIn,
    ),
    BackupState.failed || BackupState.unavailable when waiting != null =>
      const BackupMessage('Backup failed', action: BackupAction.retry),
    BackupState.offline when waiting != null => BackupMessage(
      '$waiting waiting to back up',
    ),
    _ => null,
  };
}

/// `2 sessions`, `1 session and 1 saved workout`, `3 saved workouts` — or
/// null for nothing.
String? waitingPhrase(SyncPending pending) {
  String n(int count, String one) => '$count $one${count == 1 ? '' : 's'}';
  final sessions = pending.workouts;
  final saved = pending.savedWorkouts;
  if (sessions == 0 && saved == 0) return null;
  if (saved == 0) return n(sessions, 'session');
  if (sessions == 0) return n(saved, 'saved workout');
  return '${n(sessions, 'session')} and ${n(saved, 'saved workout')}';
}

/// Each refusal, for Settings: `"Push" couldn't be backed up: a value is out of
/// range.`
String rejectionLine(RejectedWorkout r) =>
    '"${r.name}" couldn\'t be backed up: ${rejectionReason(r.detail)}.';
