/// Where a split turned over, on the ground and on the clock.
///
/// A [RunSplit] says how long a kilometre took; this says *where* it ended and
/// *when*. They are two halves of one walk over the trace (see `splitRun`), and
/// they are separate types because they are read in different places: the split
/// is a row in a list, the marker is a pin on a map.
///
/// Nothing here is stored. `run_splits` has no column for a position, and there
/// is no need for one — the trace already carries every fix's latitude,
/// longitude and timestamp, so a marker is derivable from the run whenever it
/// is drawn. Persisting it would be a second copy of a fact the trace already
/// holds, free to drift out of step with it.
class SplitMarker {
  const SplitMarker({
    required this.index,
    required this.latitude,
    required this.longitude,
    required this.at,
    required this.elapsed,
  });

  /// Which split this closes — 1 for the first kilometre, and so on. Only whole
  /// splits get a marker: a run ending at 10.18 km has ten of them, because the
  /// eleventh boundary is somewhere the runner never reached.
  final int index;

  final double latitude;
  final double longitude;

  /// The clock time the runner crossed it, interpolated within the fix that
  /// straddled the boundary for the same reason [RunSplit.duration] is — a fix
  /// lands about once a second, and a whole second of error per kilometre is
  /// visible by the end of a long run.
  final DateTime at;

  /// Time on the run's clock at the crossing: the splits before it, summed.
  ///
  /// Not `at.difference(start)`, which would charge the runner for any hole in
  /// the trace. A split's duration already has gaps taken out of it (see
  /// `splitRun`), so summing them is the only figure that agrees with the pace
  /// shown beside it.
  final Duration elapsed;

  @override
  String toString() =>
      'SplitMarker($index at $latitude, $longitude — $at, $elapsed)';
}
