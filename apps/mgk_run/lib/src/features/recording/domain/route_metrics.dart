import 'dart:math' as math;

import 'run_point.dart';

/// Fixes worse than this horizontal accuracy (in meters) are discarded before
/// they contribute to distance — poor fixes jump around and inflate the route.
/// Tunable; see docs/architecture/run-recording.md ("Accuracy filtering").
const double kMaxHorizontalAccuracyMeters = 20;

/// Accuracy good enough to **record and draw**, as opposed to good enough to
/// measure with ([kMaxHorizontalAccuracyMeters]).
///
/// These have to be two numbers, and conflating them is what made the first
/// device test look like a dead app. CoreLocation's opening fixes are routinely
/// 65 m or worse — they come from cell and wifi while the GPS chip is still
/// warming — and settle to 5–10 m only after ten to thirty seconds outdoors.
/// Under tree cover or between tall buildings, 20–35 m is simply the accuracy
/// on offer for the whole run.
///
/// Gating recording at 20 m therefore threw away *every* fix in exactly the
/// conditions people run in, so nothing was persisted, nothing was drawn, and
/// the screen sat at 0.00 km with no way to tell that from a broken GPS.
///
/// The looser gate keeps the trace, the map and the recovery marker alive; the
/// strict one still guards the number, which is the thing that has to be right.
/// A fix worse than this is genuinely useless — a 50 m error is most of a
/// street — so it is still dropped.
const double kMaxRecordableAccuracyMeters = 50;

/// Longer than this between consecutive fixes and the trace is treated as
/// **broken** rather than continuous.
///
/// Two things produce a gap: the runner paused (the recorder stops persisting
/// while paused, so the trace simply has a hole), or the signal died in a
/// tunnel or an underpass. Both look identical in the stored points, and in
/// both cases the straight line across the hole is a line nobody ran.
///
/// So distance does not accumulate across a gap and the map does not draw
/// across one. That under-counts a tunnel, which is the honest direction to be
/// wrong in: bridging instead would silently credit a runner for the taxi home.
///
/// Thirty seconds is far outside normal delivery — iOS supplies roughly a fix a
/// second with `distanceFilter: 0` — so this never fires on a healthy trace.
const Duration kMaxTraceGap = Duration(seconds: 30);

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

/// [points], accuracy-filtered and split into continuously-recorded runs of
/// fixes — one segment per unbroken stretch, broken wherever more than [maxGap]
/// passed between consecutive fixes (see [kMaxTraceGap]).
///
/// One rule, two consumers: distance must not accumulate across a gap and the
/// map must not draw across one. Deriving both from this function is what keeps
/// them from disagreeing — a pause that the total ignored but the polyline drew
/// straight through would be two answers to one question.
///
/// Segments of a single point are kept: they carry no distance, but they are a
/// real position and the map still marks them.
List<List<RunPoint>> traceSegments(
  Iterable<RunPoint> points, {
  double maxAccuracyM = kMaxHorizontalAccuracyMeters,
  Duration maxGap = kMaxTraceGap,
}) {
  final segments = <List<RunPoint>>[];
  var current = <RunPoint>[];
  RunPoint? previous;

  for (final point in points) {
    if (point.accuracyMeters > maxAccuracyM) continue;
    if (previous != null &&
        point.timestamp.difference(previous.timestamp).abs() > maxGap) {
      segments.add(current);
      current = <RunPoint>[];
    }
    current.add(point);
    previous = point;
  }

  if (current.isNotEmpty) segments.add(current);
  return segments;
}

/// Distance in meters with poor fixes dropped, sub-[minSegmentMeters] hops
/// ignored, and gaps in the trace not bridged.
///
/// Jitter first: GPS drifts by metres while a runner stands at a light, so the
/// anchor point only advances once real movement is seen and a burst of tiny
/// hops collapses to nothing while a genuine stride still counts.
///
/// Gaps second: each segment from [traceSegments] is measured on its own and
/// the holes between them contribute nothing, so a paused run no longer gains
/// the whole displacement of the pause on the first fix after resuming.
///
/// True speed-windowed autopause is still a later refinement (see
/// docs/architecture/run-recording.md).
double processedDistanceMeters(
  Iterable<RunPoint> points, {
  double maxAccuracyM = kMaxHorizontalAccuracyMeters,
  double minSegmentMeters = 1.0,
  Duration maxGap = kMaxTraceGap,
}) {
  var total = 0.0;
  for (final segment in traceSegments(
    points,
    maxAccuracyM: maxAccuracyM,
    maxGap: maxGap,
  )) {
    RunPoint? anchor;
    for (final point in segment) {
      if (anchor == null) {
        anchor = point;
        continue;
      }
      final hop = haversineMeters(
        anchor.latitude,
        anchor.longitude,
        point.latitude,
        point.longitude,
      );
      if (hop >= minSegmentMeters) {
        total += hop;
        anchor = point; // only advance on real movement
      }
    }
  }
  return total;
}

/// Total ascent so far, in metres, or null when there is none worth reporting.
///
/// Barometric only — [RunPoint.altitudeMeters] comes from CMAltimeter and GPS
/// altitude is deliberately never used, because its vertical error is several
/// times its horizontal one and summing that noise invents hundreds of metres
/// of climb on a flat run.
///
/// Rises under [kClimbNoiseMeters] are dropped rather than accumulated for the
/// same reason the distance ignores sub-metre hops: a barometer drifts while
/// you stand still, and an unfiltered sum turns that drift into a hill.
///
/// Null rather than zero below [kClimbFloorMeters]. Altitude data alone is not
/// worth a row — reporting every flat run as `0 m` is true, useless, and trains
/// the eye to skip the block on the runs where it does say something.
double? climbMeters(List<RunPoint> points) {
  double? last;
  double total = 0;
  var sawAltitude = false;

  for (final point in points) {
    final altitude = point.altitudeMeters;
    if (altitude == null) continue;
    sawAltitude = true;
    if (last == null) {
      last = altitude;
      continue;
    }
    final delta = altitude - last;
    if (delta.abs() < kClimbNoiseMeters) continue;
    if (delta > 0) total += delta;
    last = altitude;
  }

  if (!sawAltitude || total < kClimbFloorMeters) return null;
  return total;
}

/// Barometric drift while standing still, which must not read as a hill.
const double kClimbNoiseMeters = 1.0;

/// Below this, there was no climb worth reporting.
const double kClimbFloorMeters = 5.0;
