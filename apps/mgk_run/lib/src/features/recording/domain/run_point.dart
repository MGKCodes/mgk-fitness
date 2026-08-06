/// A single location sample recorded during a run.
///
/// Mirrors a `run_points` row (see docs/architecture/data-model.md). The `seq`
/// column is assigned by the persistence layer, not here.
///
/// Every point is persisted to the local store **as it arrives** — a run is
/// never held only in memory (see docs/architecture/run-recording.md).
class RunPoint {
  const RunPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    this.altitudeMeters,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in meters; larger is worse. Used to filter poor fixes.
  final double accuracyMeters;

  /// Barometric altitude in meters, if available (via CMAltimeter — see
  /// docs/architecture/run-recording.md). GPS altitude is deliberately avoided.
  final double? altitudeMeters;

  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      other is RunPoint &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.accuracyMeters == accuracyMeters &&
      other.altitudeMeters == altitudeMeters &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(
    latitude,
    longitude,
    accuracyMeters,
    altitudeMeters,
    timestamp,
  );

  @override
  String toString() =>
      'RunPoint($latitude, $longitude, acc: ${accuracyMeters}m, $timestamp)';
}
