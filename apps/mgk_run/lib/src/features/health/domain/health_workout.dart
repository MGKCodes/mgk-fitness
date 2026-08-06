/// A workout as reported by HealthKit, from some source app.
///
/// The `sourceBundleId` is the `HKSource` bundle identifier — the key signal for
/// deduplication, since the same physical run can be written to Health by the
/// watch, by Runio, and by a third-party app.
class HealthWorkout {
  const HealthWorkout({
    required this.sourceBundleId,
    required this.start,
    required this.end,
    this.distanceMeters,
    this.energyKcal,
    this.externalId,
  });

  final String sourceBundleId;
  final DateTime start;
  final DateTime end;

  /// Metric distance, if the source recorded it.
  final double? distanceMeters;
  final double? energyKcal;

  /// The `HKWorkout` UUID, used to reconcile with a stored run.
  final String? externalId;

  Duration get duration => end.difference(start);
}
