import 'dart:math' as math;

import 'run_point.dart';

/// Fixes worse than this horizontal accuracy (in meters) are discarded before
/// they contribute to distance — poor fixes jump around and inflate the route.
/// Tunable; see docs/architecture/run-recording.md ("Accuracy filtering").
const double kMaxHorizontalAccuracyMeters = 20;

/// Great-circle distance in meters between two lat/lng pairs (haversine on a
/// spherical earth). Accurate to well within GPS noise at running distances.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusM = 6371000.0;
  final dLat = _radians(lat2 - lat1);
  final dLng = _radians(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthRadiusM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _radians(double degrees) => degrees * math.pi / 180.0;

/// Total distance in meters along [points], discarding fixes worse than
/// [maxAccuracyM].
///
/// This is the raw geometric length of the accuracy-filtered trace. Jitter
/// while stationary and autopause are a later smoothing pass, not this
/// function's job — keep it a pure, exact sum so it is trivially testable
/// against a known-good trace (see docs/architecture/run-recording.md).
double routeDistanceMeters(
  Iterable<RunPoint> points, {
  double maxAccuracyM = kMaxHorizontalAccuracyMeters,
}) {
  var total = 0.0;
  RunPoint? prev;
  for (final point in points) {
    if (point.accuracyMeters > maxAccuracyM) continue;
    if (prev != null) {
      total += haversineMeters(
        prev.latitude,
        prev.longitude,
        point.latitude,
        point.longitude,
      );
    }
    prev = point;
  }
  return total;
}

/// Distance in meters with poor fixes dropped **and** sub-[minSegmentMeters]
/// hops ignored, so GPS jitter while stationary (a runner stopped at a light)
/// does not inflate the total.
///
/// The anchor point only advances once real movement is seen, so a burst of
/// tiny jitter hops collapses to nothing while a genuine stride still counts.
/// This is the first-pass smoother; true speed-windowed autopause is a later
/// refinement (see docs/architecture/run-recording.md).
double processedDistanceMeters(
  Iterable<RunPoint> points, {
  double maxAccuracyM = kMaxHorizontalAccuracyMeters,
  double minSegmentMeters = 1.0,
}) {
  var total = 0.0;
  RunPoint? anchor;
  for (final point in points) {
    if (point.accuracyMeters > maxAccuracyM) continue;
    if (anchor == null) {
      anchor = point;
      continue;
    }
    final segment = haversineMeters(
      anchor.latitude,
      anchor.longitude,
      point.latitude,
      point.longitude,
    );
    if (segment >= minSegmentMeters) {
      total += segment;
      anchor = point; // only advance on real movement
    }
  }
  return total;
}
