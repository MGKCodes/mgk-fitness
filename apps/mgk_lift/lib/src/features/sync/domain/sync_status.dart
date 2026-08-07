import 'package:meta/meta.dart';

/// What the last sync did, or why it could not run.
enum SyncOutcome {
  /// Nothing to do — everything local is already on the server.
  upToDate,

  /// Rows moved, in one direction or both.
  synced,

  /// No account. Tracking works signed out; backup cannot.
  signedOut,

  /// No network, or the server refused. **Not an error the lifter caused**, and
  /// not one that loses anything: the local database is the source of truth and
  /// the rows stay pending.
  unavailable,
}

/// The result of one sync run.
@immutable
class SyncReport {
  const SyncReport({
    required this.outcome,
    this.pushed = 0,
    this.pulled = 0,
    this.at,
    this.detail,
  });

  const SyncReport.signedOut() : this._(SyncOutcome.signedOut);
  const SyncReport.unavailable(String detail)
    : this._(SyncOutcome.unavailable, detail: detail);

  const SyncReport._(this.outcome, {this.detail})
    : pushed = 0,
      pulled = 0,
      at = null;

  final SyncOutcome outcome;
  final int pushed;
  final int pulled;
  final DateTime? at;

  /// The underlying failure, for the log. **Never shown raw to a lifter** — a
  /// PostgREST error code is not something to put in front of somebody who was
  /// trying to back up their training.
  final String? detail;

  bool get isFailure => outcome == SyncOutcome.unavailable;
}

/// What a lifter has waiting to upload.
@immutable
class SyncPending {
  const SyncPending({required this.workouts, required this.lastSyncedAt});

  /// Finished sessions not yet on the server.
  final int workouts;

  final DateTime? lastSyncedAt;

  bool get hasWork => workouts > 0;
}
