import 'health_workout.dart';

/// Runio's own HealthKit source bundle id. Its recordings carry the GPS trace,
/// so they win when the same run is reported by multiple sources.
const String runioSourceBundleId = 'com.mgkcodes.runio';

/// Collapses workouts that are the **same physical run** into one.
///
/// The classic HealthKit duplicate: a single run written to Health by the watch,
/// by Runio, and by a third-party app, all overlapping in time. Workouts whose
/// time windows overlap (within [tolerance], to absorb small clock skew between
/// devices) are treated as one run, and the best-sourced representative is kept:
///
/// 1. the [preferredSourceBundleId] (Runio — it has the trace), else
/// 2. one that actually has a distance, else
/// 3. the longest, else
/// 4. the earliest (stable tiebreak).
///
/// This is the app's highest-risk area (docs/architecture/run-recording.md):
/// invisible in single-device testing, immediately obvious in the wild — hence
/// it is pure and fixture-tested.
List<HealthWorkout> dedupeWorkouts(
  Iterable<HealthWorkout> workouts, {
  String preferredSourceBundleId = runioSourceBundleId,
  Duration tolerance = const Duration(minutes: 1),
}) {
  final sorted = workouts.toList()..sort((a, b) => a.start.compareTo(b.start));

  final clusters = <List<HealthWorkout>>[];
  DateTime? clusterEnd;
  for (final workout in sorted) {
    final startsNewRun =
        clusterEnd == null || workout.start.isAfter(clusterEnd.add(tolerance));
    if (startsNewRun) {
      clusters.add(<HealthWorkout>[workout]);
      clusterEnd = workout.end;
    } else {
      clusters.last.add(workout);
      if (workout.end.isAfter(clusterEnd)) clusterEnd = workout.end;
    }
  }

  return <HealthWorkout>[
    for (final cluster in clusters)
      _representative(cluster, preferredSourceBundleId),
  ];
}

HealthWorkout _representative(List<HealthWorkout> cluster, String preferred) {
  cluster.sort((a, b) {
    final preferredCmp = _rank(a, preferred) - _rank(b, preferred);
    if (preferredCmp != 0) return preferredCmp;

    final aHasDistance = a.distanceMeters != null ? 0 : 1;
    final bHasDistance = b.distanceMeters != null ? 0 : 1;
    if (aHasDistance != bHasDistance) return aHasDistance - bHasDistance;

    final durationCmp = b.duration.compareTo(a.duration); // longer first
    if (durationCmp != 0) return durationCmp;

    return a.start.compareTo(b.start); // earliest first
  });
  return cluster.first;
}

int _rank(HealthWorkout w, String preferred) =>
    w.sourceBundleId == preferred ? 0 : 1;
