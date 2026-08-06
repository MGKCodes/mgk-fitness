import 'run_point.dart';

/// The lifecycle state of a [RunRecorder].
enum RecorderStatus { idle, recording, paused, stopped }

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
