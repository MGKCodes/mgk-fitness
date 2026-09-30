import '../domain/run_point.dart';

/// The device location stream, abstracted so the recording engine is swappable
/// and testable. The initial concrete implementation is `geolocator`-backed; a
/// fake feeds canned fixes in tests.
///
/// Fixes here are **raw and unfiltered** — accuracy filtering and persistence
/// are the recorder's job (see docs/architecture/run-recording.md).
abstract interface class LocationSource {
  /// Raw location fixes as they arrive from the device.
  ///
  /// Failures that happen *after* a successful [start] — the runner revoking
  /// permission mid-run, the platform giving up on the stream — arrive as
  /// errors on this stream rather than silently ending it. A source that goes
  /// quiet is indistinguishable from a runner standing still, and that
  /// ambiguity is what a whole run gets lost in.
  Stream<RunPoint> get fixes;

  /// Begins delivering fixes on [fixes].
  ///
  /// Throws [LocationUnavailable] when the device will not supply location at
  /// all — services switched off, or permission refused.
  Future<void> start();

  /// Stops delivering fixes and releases the underlying location service.
  Future<void> stop();
}

/// Why the device will not supply location.
///
/// Separate cases because the remedy differs and the app has to name it: an
/// app-settings deep link is useless when it is the system location switch that
/// is off, and offering to re-ask is a lie once the answer is "never".
enum LocationUnavailableReason {
  /// Location Services are switched off device-wide.
  servicesDisabled,

  /// Permission was refused for now, and can be asked for again.
  permissionDenied,

  /// Permission was refused permanently. Only Settings can change it.
  permissionDeniedForever,

  /// Permission is granted, but only to approximate location (iOS "Precise
  /// Location" off, or Android's "Approximate" grant) — fixes arrive with
  /// horizontal accuracy on the order of a kilometre or more.
  ///
  /// Distinct from every other reason here: the platform is not refusing
  /// anything, so [LocationSource.start] does not fail on its own account —
  /// every fix simply lands worse than the recorder's own accuracy floor and
  /// is discarded before it reaches it, silently, with no error on the
  /// stream at all. This reason exists so a source that can *ask* the
  /// authorisation status (geolocator's `getLocationAccuracy`) can say so
  /// before a run spends its whole distance on "Acquiring GPS". Only
  /// Settings can change it.
  reducedAccuracy,

  /// The platform failed for some other reason — see [LocationUnavailable.cause].
  failed,
}

/// Thrown by [LocationSource.start], and delivered on [LocationSource.fixes],
/// when location is not available.
///
/// A refused permission is a designed-for outcome rather than a crash — the
/// same rule the health-data layer follows, for the same reason: the runner
/// made a choice and the app's job is to say what that choice costs them, not
/// to fall over.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.reason, [this.cause]);

  final LocationUnavailableReason reason;

  /// The underlying platform error, when there was one.
  final Object? cause;

  @override
  String toString() =>
      'LocationUnavailable(${reason.name}${cause == null ? '' : ': $cause'})';
}
