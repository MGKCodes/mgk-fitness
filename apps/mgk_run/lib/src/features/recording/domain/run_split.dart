/// One split of a run — usually a kilometre (the last may be shorter). Mirrors
/// a `run_splits` row. Metric; pace/HR are derived at the display layer.
class RunSplit {
  const RunSplit({
    required this.index,
    required this.distanceMeters,
    required this.duration,
    this.avgHr,
  });

  /// 1-based position of this split within the run.
  final int index;
  final double distanceMeters;
  final Duration duration;
  final int? avgHr;
}
