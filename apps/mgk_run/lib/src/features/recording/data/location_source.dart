import '../domain/run_point.dart';

/// The device location stream, abstracted so the recording engine is swappable
/// and testable. The initial concrete implementation is `geolocator`-backed; a
/// fake feeds canned fixes in tests.
///
/// Fixes here are **raw and unfiltered** — accuracy filtering and persistence
/// are the recorder's job (see docs/architecture/run-recording.md).
abstract interface class LocationSource {
  /// Raw location fixes as they arrive from the device.
  Stream<RunPoint> get fixes;

  /// Begins delivering fixes on [fixes].
  Future<void> start();

  /// Stops delivering fixes and releases the underlying location service.
  Future<void> stop();
}
