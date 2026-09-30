import '../../sync/domain/sync_status.dart';

/// Uploads and restores progress photos.
///
/// **Separate from [BackupService], which carries the training log.** Two
/// reasons, and both are about failure rather than tidiness.
///
/// A photo is megabytes over a storage API; a session is a few dozen text rows
/// over PostgREST. Folding them into one run means a lifter on a bad connection
/// loses their *training* backup to a stalled image upload, which is the wrong
/// thing to sacrifice — the log is the part that cannot be re-derived from a
/// phone's camera roll.
///
/// And photos are paid. `BackupService` runs for anybody signed in, because
/// tracking and syncing it are free (ADR-0008's "tracking is never gated"); this
/// runs only when the account is entitled. One class with a boolean would put
/// that rule inside the thing it is meant to constrain.
///
/// Reuses [SyncReport] rather than declaring a parallel one. A push count, a
/// pull count and "could not reach the server" describe both jobs exactly, and
/// two shapes for one idea is how the two halves of Settings start disagreeing
/// about what "synced" means.
abstract interface class PhotoBackup {
  /// Pushes local photos, then pulls remote ones.
  Future<SyncReport> run();

  /// How many photos exist only on this device.
  Future<int> pendingUploads();
}
