import '../../settings/domain/backup_health.dart';

/// What Profile can honestly say about the backup, in one value.
///
/// **Deliberately not Lift's `SyncPending`.** Lift's sync is manual, so a count
/// of what is waiting is a standing fact worth showing — its own bar says
/// *"3 sessions waiting to upload"* and offers a *Sync now* button. Run's is
/// automatic: every write pushes, and a launch backfills whatever the server is
/// missing. A pending count here would be transiently zero and would read as a
/// claim the app has not earned, on the one page whose doc says *"a dash is an
/// absence, a zero is a claim"*.
///
/// So this carries only what is true without asking the server: whether
/// something is in flight, what the last attempt did, and whether there is
/// anywhere for the data to go at all.
class ProfileBackupState {
  const ProfileBackupState({
    required this.signedIn,
    required this.consented,
    required this.syncing,
    required this.health,
    this.justSent = 0,
  });

  /// There is an account to attribute rows to. Without one the log is on the
  /// phone and nowhere else, which is a state to state plainly rather than a
  /// failure to warn about (ADR-0019).
  final bool signedIn;

  /// Backup was asked for and granted (ADR-0012).
  final bool consented;

  /// Something is in flight right now — a restore, or a backfill.
  final bool syncing;

  /// Runs the last backfill actually pushed.
  ///
  /// **Free, and thrown away until now.** `SupabaseRunBackup.backfill` has
  /// always returned the count it sent, and both callers in `HomeShell`
  /// discarded it with `.catchError((_) => 0)`. It is the only figure here that
  /// says something happened rather than something is true.
  final int justSent;

  /// The last attempt's outcome, from the local record Settings already reads.
  final BackupHealth health;

  /// Whether there is anything worth drawing. A runner with no account and no
  /// consent has nothing to report and should not be shown an empty card.
  bool get isWorthShowing => signedIn && consented;
}
