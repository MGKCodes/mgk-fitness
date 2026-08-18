import 'package:mgk_units/mgk_units.dart';

import 'route_metrics.dart';
import 'run_point.dart';
import 'run_split.dart';

/// How much of the recent trace a live pace is measured over.
///
/// Long enough that GPS noise averages out, short enough to answer the question
/// a runner is actually asking — "am I going too fast *now*" — rather than the
/// one a cumulative average answers, which is "how has the whole run gone".
const Duration kLivePaceWindow = Duration(seconds: 30);

/// Below this much movement over [kLivePaceWindow], there is no honest pace to
/// report. A runner covers ~90 m in thirty seconds at 5:30/km; 25 m is walking
/// pace and below, where the quotient is mostly noise.
const double kLivePaceMinMeters = 25;

/// How much to trust the position on screen.
///
/// Reported because a runner cannot otherwise tell a stationary app from a
/// searching one, and the first device test could not tell either.
enum GpsSignal {
  /// No fix at all yet.
  none,

  /// Usable for a position, not for a measurement — the fix is recorded and
  /// drawn but does not move the distance.
  weak,

  /// Good enough to measure with, but visibly loose.
  fair,

  /// What an open sky gives.
  good;

  /// Whether distance is accumulating at this level.
  bool get measures => this == fair || this == good;
}

/// How old the newest fix may be before the signal counts as gone.
///
/// Fixes land about once a second, so a gap this long is not jitter. Short
/// enough that a runner entering an underpass sees it while they are still in
/// there; long enough to ride out the handful of seconds a phone loses when it
/// is switched between cell and GPS positioning, which is not worth an alarm.
const Duration kStaleFixAfter = Duration(seconds: 15);

/// The signal implied by the newest fix, given how long ago it arrived.
///
/// **Age is half the answer and used to be missing entirely.** Strength was
/// read off the newest fix's accuracy alone, so a five-minute-old fix taken in
/// an open sky still reported three bars: the screen went on claiming a good
/// signal, over a distance that had stopped moving, for as long as the runner
/// cared to look. That is the shape of the failure — nothing errors, so nothing
/// says anything — and it is why [sinceFix] is required rather than optional.
/// An optional age defaulting to "don't check" is exactly the reasoning that
/// let the bug exist.
GpsSignal gpsSignalFor(RunPoint? fix, {required Duration? sinceFix}) {
  if (fix == null) return GpsSignal.none;
  if (sinceFix != null && sinceFix >= kStaleFixAfter) return GpsSignal.none;
  final accuracy = fix.accuracyMeters;
  if (accuracy > kMaxHorizontalAccuracyMeters) return GpsSignal.weak;
  if (accuracy > 10) return GpsSignal.fair;
  return GpsSignal.good;
}

/// Pace over the trailing [window], or null when there is not enough recent
/// movement to say.
///
/// Null is a real answer here, not a gap: at the start of a run, standing at a
/// light, or with the signal gone, there is no current pace, and a plausible
/// wrong number is worse than an honest absence. The screen renders dashes.
Pace? rollingPace(
  List<RunPoint> points, {
  Duration window = kLivePaceWindow,
  double minMeters = kLivePaceMinMeters,
}) {
  if (points.length < 2) return null;
  final end = points.last.timestamp;
  final cutoff = end.subtract(window);

  final recent = <RunPoint>[
    for (final point in points)
      if (!point.timestamp.isBefore(cutoff) &&
          point.accuracyMeters <= kMaxHorizontalAccuracyMeters)
        point,
  ];
  if (recent.length < 2) return null;

  final elapsed = recent.last.timestamp.difference(recent.first.timestamp);
  if (elapsed <= Duration.zero) return null;

  // The processed distance, so the live pace and the live total are computed
  // the same way and cannot tell different stories about the same stretch.
  final meters = processedDistanceMeters(recent);
  if (meters < minMeters) return null;

  return Pace.from(Distance.meters(meters), elapsed);
}

/// The run so far, cut into splits of [splitMeters].
///
/// The trailing partial split is included and flagged by its distance being
/// short — a runner 600 m into their fourth kilometre wants to see that, and
/// the summary already renders a short final split the same way.
///
/// Timing is interpolated within the fix that crosses each boundary, because a
/// fix lands every second or so and a whole second of error per split
/// accumulates visibly over a long run.
List<RunSplit> splitsFor(
  List<RunPoint> points, {
  double splitMeters = 1000,
  bool includePartial = true,
}) {
  final splits = <RunSplit>[];
  var index = 1;
  var covered = 0.0; // metres into the current split
  DateTime? splitStart;
  RunPoint? anchor;
  DateTime? lastSeen;

  for (final segment in traceSegments(points)) {
    // A new segment means recording stopped and restarted. The distance across
    // the hole is not measured (nobody knows the path), and the time is not
    // charged to the split either — a runner who paused for coffee did not run
    // a twenty-minute kilometre. Sliding the split's start forward by the gap
    // is what keeps the pace honest on both sides of it.
    if (lastSeen != null && splitStart != null) {
      splitStart = splitStart.add(segment.first.timestamp.difference(lastSeen));
    }
    anchor = null;

    for (final point in segment) {
      if (anchor == null) {
        anchor = point;
        splitStart ??= point.timestamp;
        lastSeen = point.timestamp;
        continue;
      }

      final hop = haversineMeters(
        anchor.latitude,
        anchor.longitude,
        point.latitude,
        point.longitude,
      );
      // Jitter, by the same rule processedDistanceMeters uses — the anchor is
      // not advanced, so a burst of tiny hops collapses rather than counting.
      if (hop < 1.0) continue;

      final hopMs = point.timestamp
          .difference(anchor.timestamp)
          .inMilliseconds
          .clamp(0, 1 << 30);

      // Metres of THIS hop already spent closing earlier splits. One hop can
      // close more than one when the signal has been sparse, so this loops.
      var spent = 0.0;
      while (covered + (hop - spent) >= splitMeters) {
        spent += splitMeters - covered;
        // Constant speed across the hop, so the crossing time is the fraction
        // of the hop consumed. A whole second of error per split is visible
        // over a long run, which is why this interpolates at all.
        final crossedAt = anchor.timestamp.add(
          Duration(milliseconds: (hopMs * (spent / hop)).round()),
        );
        splits.add(
          RunSplit(
            index: index++,
            distanceMeters: splitMeters,
            duration: crossedAt.difference(splitStart!),
          ),
        );
        splitStart = crossedAt;
        covered = 0;
      }

      covered += hop - spent;
      anchor = point;
      lastSeen = point.timestamp;
    }
  }

  if (includePartial && covered > 0 && splitStart != null && lastSeen != null) {
    splits.add(
      RunSplit(
        index: index,
        distanceMeters: covered,
        duration: lastSeen.difference(splitStart),
      ),
    );
  }

  return splits;
}
