import 'package:meta/meta.dart';

/// What the last sync did, or why it could not run.
enum SyncOutcome {
  /// Nothing to do — everything local is already on the server.
  upToDate,

  /// Rows moved, in one direction or both.
  synced,

  /// No account. Tracking works signed out; syncing cannot.
  signedOut,

  /// No network, or the server refused. **Not an error the lifter caused**, and
  /// not one that loses anything: the local database is the source of truth and
  /// the rows stay pending.
  unavailable,
}

/// Why a backup — or one workout in it — did not go up.
///
/// **Each one reads differently to a lifter and is handled differently here**,
/// which is the reason for the split. The old report had one failure, and so
/// one sentence for all of them: "could not reach the server", said about a
/// row the server had reached and refused.
enum BackupProblem {
  /// No connection. Automatic: it goes up when there is one.
  offline,

  /// No account on this device. Needs the lifter to sign in.
  signedOut,

  /// Signed in, but the server no longer accepts the session. Needs the lifter
  /// to sign in again.
  expired,

  /// The server refused **this workout** — a value it will not store. The
  /// rest carry on; this one waits until it is edited, because sending the
  /// same row again gets the same answer.
  rejected,

  /// The server failed, or took too long. Retried on its own.
  server,

  /// Backup is misconfigured on the server side — a schema or function it
  /// cannot find. Nothing the lifter can do; retried later.
  unavailable,
}

/// A failure the backup layer understands — the one exception type the
/// uploader handles, so the Supabase client's own exceptions never leak past
/// the class that talks to it.
@immutable
class BackupFailure implements Exception {
  const BackupFailure(this.problem, this.detail);

  final BackupProblem problem;

  /// The underlying `code: message`, **for the log only**.
  final String detail;

  @override
  String toString() => 'BackupFailure(${problem.name}: $detail)';
}

/// The result of one sync run.
@immutable
class SyncReport {
  const SyncReport({
    required this.outcome,
    this.pushed = 0,
    this.pulled = 0,
    this.rejected = 0,
    this.at,
    this.detail,
    this.problem,
  });

  const SyncReport.signedOut()
    : this._(SyncOutcome.signedOut, problem: BackupProblem.signedOut);
  const SyncReport.unavailable(String detail, {BackupProblem? problem})
    : this._(
        SyncOutcome.unavailable,
        detail: detail,
        problem: problem ?? BackupProblem.server,
      );

  const SyncReport._(this.outcome, {this.detail, this.problem})
    : pushed = 0,
      pulled = 0,
      rejected = 0,
      at = null;

  final SyncOutcome outcome;
  final int pushed;
  final int pulled;

  /// Workouts the server refused on this run. The run itself can still have
  /// succeeded: one bad row no longer stops the rest.
  final int rejected;
  final DateTime? at;

  /// The underlying failure, for the log. **Never shown raw to a lifter** — a
  /// PostgREST error code is not something to put in front of somebody who was
  /// trying to back up their training.
  final String? detail;

  /// Why the run stopped, when it did; null for a run that finished.
  final BackupProblem? problem;

  bool get isFailure => outcome == SyncOutcome.unavailable;
}

/// A workout the server refused, and why.
@immutable
class RejectedWorkout {
  const RejectedWorkout({
    required this.id,
    required this.name,
    required this.isTemplate,
    required this.detail,
  });

  final String id;
  final String name;

  /// A saved workout rather than a session — which decides where "Open it"
  /// goes.
  final bool isTemplate;

  /// The raw refusal, for [rejectionReason].
  final String detail;
}

/// What a lifter has waiting to upload.
@immutable
class SyncPending {
  const SyncPending({
    required this.workouts,
    required this.lastSyncedAt,
    this.savedWorkouts = 0,
    this.waitingIds = const <String>{},
    this.rejected = const <RejectedWorkout>[],
  });

  /// **Sessions** not yet on the server and still being tried. The name is
  /// older than saved workouts going up; every sentence built on it says
  /// "sessions", so it stays sessions and the library has its own count.
  /// Refused ones are counted in [rejected] instead.
  final int workouts;

  /// Saved workouts not yet on the server.
  final int savedWorkouts;

  final DateTime? lastSyncedAt;

  /// Which ones, so a surface can mark a row or say whether *this* session is
  /// backed up.
  final Set<String> waitingIds;

  /// Refused by the server, each with its reason.
  final List<RejectedWorkout> rejected;

  bool get hasWork => workouts > 0 || savedWorkouts > 0;

  /// Anything on this device the server does not have.
  bool isBackedUp(String id) =>
      !waitingIds.contains(id) && !rejected.any((r) => r.id == id);
}

/// The sentence for a refusal: what was wrong, in words, never the code.
///
/// Keyed on the SQLSTATE class where there is one. Anything unrecognised gets
/// the plain version rather than a guess.
String rejectionReason(String detail) {
  final code = detail.split(':').first.trim();
  return switch (code) {
    '22003' || '22008' => 'a value is out of range',
    '23502' => 'something it needs is missing',
    '23514' || '23P01' => 'a value isn\'t allowed',
    '22P02' || '22007' => 'a value isn\'t in the right form',
    '42501' => 'it belongs to a different account',
    _ => 'the server wouldn\'t take it',
  };
}

/// Backing the training log up to an account, and saying what is waiting.
///
/// The shell held the concrete sync class before this existed, which was the
/// one place a screen named a data-layer class. It cost more than tidiness: that
/// class reaches the on-device database, the database reaches `dart:ffi`, and
/// `dart:ffi` does not exist on the web — so importing it from the shell put the
/// entire native stack in the import graph of every screen. The preview harness
/// could not be compiled for a browser at all, despite passing nothing but
/// fakes, and `main.dart`'s claim that the widgets "take interfaces, so a test
/// or the preview harness passes fakes and never needs a database" was false in
/// exactly one place.
///
/// Two methods, because two is what the shell uses. A wider interface would be
/// inventing requirements for the fake that implements it.
abstract interface class BackupService {
  /// What is waiting to upload, and when the last run succeeded.
  Future<SyncPending> pending();

  /// Push what is pending, pull what is missing. Never throws — a failure is a
  /// [SyncReport] with [SyncOutcome.unavailable], because the local database is
  /// the source of truth and nothing is lost by a sync that did not happen.
  Future<SyncReport> run();
}
