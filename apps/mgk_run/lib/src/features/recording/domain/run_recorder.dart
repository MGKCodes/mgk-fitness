import 'run_point.dart';

/// The lifecycle state of a [RunRecorder].
///
/// "Acquiring" is deliberately not one of these. Waiting for the first fix is
/// not a lifecycle state — the recorder is recording, it simply has nothing
/// yet — and it is already answerable from [RunRecorder.lastFix] being null.
/// Adding it here would mean every `switch` on lifecycle had to handle a case
/// that is really about data.
enum RecorderStatus { idle, recording, paused, stopped }

/// Why a recorder cannot record.
///
/// Distinct from [RecorderStatus]: the status says what the recorder is trying
/// to do, this says what is stopping it. A recorder can be `recording` and
/// problem-free but fixless (still acquiring), or `recording` with a problem
/// (permission revoked mid-run) — one field cannot carry both.
enum RecorderProblem {
  /// Location Services are switched off device-wide. Only the system Settings
  /// app can change this; the app-settings deep link does not reach it.
  locationServicesOff,

  /// Permission refused, and can be asked for again.
  permissionDenied,

  /// Permission refused permanently. Re-asking does nothing — Settings only.
  permissionDeniedForever,

  /// The location source failed for some other reason.
  locationFailed,
}

/// Captures a run from a location source.
///
/// This interface is the seam that keeps the recording engine swappable: the
/// app depends on this abstraction, and a concrete implementation (initially
/// geolocator-based) supplies the points. If real-world use shows dropped
/// points, changing engines is a one-class change rather than a rewrite.
///
/// Implementation contract:
/// - Every [RunPoint] emitted on [points] MUST already be persisted to the
///   local store. A crash mid-run must not lose the run.
/// - Poor-accuracy fixes should be filtered before they reach [points].
///
/// See docs/architecture/run-recording.md.
abstract interface class RunRecorder {
  /// Points as they are recorded (already persisted when emitted).
  Stream<RunPoint> get points;

  /// Emits on every [status] transition.
  Stream<RecorderStatus> get statusChanges;

  /// The current lifecycle status.
  RecorderStatus get status;

  /// What is stopping the recorder, or null when nothing is.
  ///
  /// Set rather than thrown, because [start] is called from `initState` where
  /// there is nobody to catch anything: the previous version's exception became
  /// an unhandled async error and the screen showed a pulsing "Recording" over
  /// permanently zeroed stats.
  RecorderProblem? get problem;

  /// Emits on every [problem] change, including back to null when one clears.
  Stream<RecorderProblem?> get problems;

  /// The most recent accepted fix, or null before the first one lands.
  ///
  /// Null while recording means "acquiring" — the honest state for the first
  /// ten to thirty seconds of any run, and one the screen has to be able to
  /// name rather than render as zeroes.
  RunPoint? get lastFix;

  /// Time on the run's clock: wall time since the start, minus anything the
  /// runner explicitly paused.
  ///
  /// **Only the runner stops this clock, and only by pressing Pause.** A pause
  /// is a deliberate act and the clock owes them it. Merely stopping running is
  /// not one — waiting at a crossing is part of your 10k the way it is part of
  /// a race — so no heuristic may stop this.
  ///
  /// Derived from the wall clock rather than accumulated from a ticker: a timer
  /// is throttled and then suspended when iOS backgrounds the app, so a run
  /// with the screen locked came back having "lost" the minutes it was away.
  Duration get elapsed;

  Future<void> start();

  Future<void> pause();

  Future<void> resume();

  /// Stops recording and releases the location source, finalizing the run.
  Future<void> stop();

  /// Cancels the run: stops recording and **deletes** its local data, so nothing
  /// is saved and the unfinished row isn't later treated as recoverable. Use for
  /// a deliberate discard, as opposed to [stop] which finalizes.
  Future<void> discard();
}
