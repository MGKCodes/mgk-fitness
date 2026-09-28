import 'route_metrics.dart';
import 'run_point.dart';

/// The distances a personal best is kept at.
///
/// The four a runner says out loud, and the same four
/// `raceName()` in `coaching/domain/prescribed_distance.dart` has a word for.
/// The two lists are checked against each other by a test rather than shared in
/// code, because the dependency would run the wrong way: every feature depends
/// on `recording/domain` and it depends on none of them, and importing the
/// coach's naming here to save four numbers would put a cycle in for the sake
/// of a constant.
///
/// Stored exactly. A marathon is 42,195 m — not 42 km — and the whole point of
/// searching a trace for a window is that the window is the real distance.
const List<double> kRecordDistancesMeters = <double>[
  5000,
  10000,
  21097.5,
  42195,
];

/// **A best effort is the fastest continuous stretch of a distance *inside* a
/// run, not the run's own time.**
///
/// The distinction is the whole reason this type exists, and the alternative is
/// wrong in the way that is hardest to notice: it looks right. The 23 Aug test
/// run covered 10.18 km in 58:28. Read as a 10K personal best that is 58:28,
/// and the runner's actual 10K time inside it was about 57:25 — so treating the
/// whole run as the record understates their own best by a minute and never
/// says it is doing so. It gets worse the further past the mark they went: a
/// 21.5 km training run reported as a half marathon is a wildly slow half
/// marathon, and there is nothing on the screen to tell the runner why.
///
/// So a record is searched for, over the trace, with a sliding window.
class BestEffort {
  const BestEffort({required this.distanceMeters, required this.duration});

  /// One of [kRecordDistancesMeters], in metres. Metric stored, converted at
  /// display (CLAUDE.md rule 4).
  final double distanceMeters;

  /// How long the fastest continuous stretch of [distanceMeters] took.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is BestEffort &&
      other.distanceMeters == distanceMeters &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(distanceMeters, duration);

  @override
  String toString() => 'BestEffort(${distanceMeters}m in $duration)';
}

/// Float noise, in metres, not a tolerance anybody chose.
///
/// A trace laid out to be exactly 5,000 m long sums, through fifty haversines
/// and fifty additions, to 4,999.999999997 — and a run that is exactly the
/// distance has to count as that distance. A micrometre is far below anything a
/// GPS or a runner can mean, so nothing about the answer changes; the only
/// thing this buys is that the exact case does not fall off the edge.
const double _epsilonMeters = 1e-6;

/// The fastest continuous [meters] anywhere in [points], or null when the trace
/// does not contain that distance at all.
///
/// **Null is the ordinary answer, not a failure.** A run shorter than the
/// distance has no window to find, and a run with no trace — hand-entered, or
/// pulled in from Health — has no interior to search. Both contribute nothing,
/// and deliberately: the whole-run time is a different measurement, and mixing
/// the two kinds of evidence into one records table is how the table stops
/// meaning anything (ADR-0026).
///
/// The trace is walked the way distance is walked, and that is not a detail:
/// [traceSegments] drops fixes too inaccurate to measure with and refuses to
/// bridge a gap, and hops under a metre are jitter and do not advance the
/// anchor. A window measured by a different rule than the run's own distance
/// would reach 10 km at a different place than the run says it did.
///
/// A window never spans a gap. The straight line across a hole in the trace is
/// a line nobody ran, and crediting a runner with the tunnel would be crediting
/// them with the fastest kilometre of the run.
Duration? fastestEffort(List<RunPoint> points, double meters) {
  if (meters <= 0) return null;
  return _fastest(_profiles(points), meters);
}

/// Every record this trace holds, shortest distance first.
///
/// One walk over the trace for all four, because it is the same walk: the
/// distance/time profile is built once and each distance is a scan over it.
///
/// A distance the run does not contain is **absent from the list** rather than
/// present with a null — there is no such record, and a row saying so would be
/// a stored zero by another name.
List<BestEffort> bestEffortsFor(
  List<RunPoint> points, {
  List<double> distances = kRecordDistancesMeters,
}) {
  final profiles = _profiles(points);
  if (profiles.isEmpty) return const <BestEffort>[];

  final efforts = <BestEffort>[];
  for (final meters in distances) {
    if (meters <= 0) continue;
    final duration = _fastest(profiles, meters);
    if (duration != null) {
      efforts.add(BestEffort(distanceMeters: meters, duration: duration));
    }
  }
  efforts.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return efforts;
}

/// One continuously-recorded stretch, as two parallel ladders: metres covered
/// so far, and the clock at that point.
///
/// Parallel lists rather than a list of pairs because every scan over them is
/// an index walk, and the arithmetic reads better with the two apart.
class _Profile {
  _Profile(this.meters, this.atMs);

  /// Cumulative metres, starting at 0 and strictly increasing — a hop under the
  /// jitter floor never makes it in, so no two entries are equal.
  final List<double> meters;

  /// Wall clock at each entry, in milliseconds. Milliseconds rather than
  /// seconds because the interpolation is the point: a fix lands every second
  /// or so, and rounding each window edge to a whole second gives back exactly
  /// the error the interpolation exists to remove.
  final List<int> atMs;

  double get total => meters.isEmpty ? 0 : meters.last;
}

List<_Profile> _profiles(List<RunPoint> points) {
  final profiles = <_Profile>[];
  for (final segment in traceSegments(points)) {
    final meters = <double>[];
    final atMs = <int>[];
    RunPoint? anchor;
    var covered = 0.0;

    for (final point in segment) {
      if (anchor == null) {
        anchor = point;
        meters.add(0);
        atMs.add(point.timestamp.millisecondsSinceEpoch);
        continue;
      }
      final hop = haversineMeters(
        anchor.latitude,
        anchor.longitude,
        point.latitude,
        point.longitude,
      );
      // Jitter, by the rule processedDistanceMeters and splitRun both use: the
      // anchor does not advance, so a burst of tiny hops while a runner stands
      // at a light collapses to nothing instead of accumulating. The time it
      // took still counts — the next accepted fix carries its own clock — which
      // is right, because standing at the light is part of the effort.
      if (hop < 1.0) continue;
      covered += hop;
      meters.add(covered);
      atMs.add(point.timestamp.millisecondsSinceEpoch);
      anchor = point;
    }

    if (meters.length >= 2) profiles.add(_Profile(meters, atMs));
  }
  return profiles;
}

Duration? _fastest(List<_Profile> profiles, double meters) {
  int? best;
  for (final profile in profiles) {
    final ms = _fastestWindowMs(profile, meters);
    if (ms != null && (best == null || ms < best)) best = ms;
  }
  return best == null ? null : Duration(milliseconds: best);
}

/// The shortest time covering exactly [target] metres somewhere in [profile].
///
/// **Both edges are interpolated, and neither is snapped to a fix.** Points
/// arrive every few seconds, so snapping the window to whole fixes can be tens
/// of metres out at each end — at 10 km that is a real number of seconds, and
/// it lands on the side that flatters or robs the runner at random.
///
/// Two passes, because the answer can sit at either kind of boundary. Think of
/// the window sliding continuously along the route: within a single hop the
/// speed is constant, so the elapsed time is a piecewise-linear function of
/// where the window starts, and it changes slope only where one of the two
/// edges crosses a recorded fix. A piecewise-linear function takes its minimum
/// at a corner, so checking every window that *ends* on a fix (pass one) and
/// every window that *starts* on one (pass two) checks every corner there is.
/// One pass alone silently misses windows whose best position has the other
/// edge pinned, and the miss is invisible: it returns a real time from a real
/// stretch of road, just not the fastest one.
int? _fastestWindowMs(_Profile profile, double target) {
  final meters = profile.meters;
  final atMs = profile.atMs;
  final n = meters.length;
  if (profile.total + _epsilonMeters < target) return null;

  int? best;
  void offer(int ms) {
    if (best == null || ms < best!) best = ms;
  }

  // Pass one: the window ends on a fix, so its start is interpolated.
  var from = 0;
  for (var end = 1; end < n; end++) {
    final startsAt = meters[end] - target;
    if (startsAt < -_epsilonMeters) continue;
    while (from + 1 < end && meters[from + 1] <= startsAt) {
      from++;
    }
    offer(atMs[end] - _clockAt(profile, from, startsAt));
  }

  // Pass two: the window starts on a fix, so its end is interpolated.
  var to = 1;
  for (var start = 0; start < n - 1; start++) {
    final endsAt = meters[start] + target;
    if (endsAt > profile.total + _epsilonMeters) break;
    if (to <= start) to = start + 1;
    while (to + 1 < n && meters[to] < endsAt) {
      to++;
    }
    offer(_clockAt(profile, to - 1, endsAt) - atMs[start]);
  }

  return best;
}

/// The clock at [position] metres, interpolated inside the hop that begins at
/// [index].
///
/// Constant speed across a hop — the same assumption `splitRun` interpolates a
/// split boundary with, and over the second or so a hop covers the difference
/// between that and reality is far inside GPS noise.
int _clockAt(_Profile profile, int index, double position) {
  final span = profile.meters[index + 1] - profile.meters[index];
  final into = position - profile.meters[index];
  final fraction = span <= 0 ? 0.0 : (into / span).clamp(0.0, 1.0);
  final from = profile.atMs[index];
  return (from + (profile.atMs[index + 1] - from) * fraction).round();
}
