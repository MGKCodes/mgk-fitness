import '../../recording/domain/run_summary.dart';

/// Lifetime totals and bests, derived from the runs on the device.
///
/// Derived rather than stored: the runs are the source of truth, so a total that
/// disagreed with them would be a bug waiting to happen. Recomputing a few
/// hundred rows is free next to keeping a second copy honest.
///
/// Everything is nullable-by-absence rather than zero. A runner with no runs has
/// no fastest pace — showing `0:00 /km` would be a lie, and the design rule is to
/// handle missing data as normal rather than as an error (CLAUDE.md rule 6).
class RunnerStats {
  const RunnerStats({
    required this.runCount,
    required this.totalMeters,
    required this.totalDuration,
    this.longestRunMeters,
    this.fastestPaceSecondsPerKm,
    this.firstRunAt,
    this.currentStreakWeeks = 0,
  });

  final int runCount;
  final double totalMeters;
  final Duration totalDuration;
  final double? longestRunMeters;
  final double? fastestPaceSecondsPerKm;
  final DateTime? firstRunAt;

  /// Consecutive weeks, counting back from the most recent run's week, that
  /// contain at least one run.
  final int currentStreakWeeks;

  bool get isEmpty => runCount == 0;

  static const RunnerStats empty = RunnerStats(
    runCount: 0,
    totalMeters: 0,
    totalDuration: Duration.zero,
  );

  /// Folds a run list into its totals in a single pass.
  /// [now] decides whether a streak is still running. Injected rather than
  /// read from the clock so "has it lapsed" is testable without waiting a week.
  factory RunnerStats.from(List<RunSummary> runs, {DateTime? now}) {
    if (runs.isEmpty) return empty;

    var totalMeters = 0.0;
    var totalDuration = Duration.zero;
    double? longest;
    double? fastest;
    DateTime? first;

    for (final run in runs) {
      totalMeters += run.distanceMeters;
      totalDuration += run.duration;

      if (longest == null || run.distanceMeters > longest) {
        longest = run.distanceMeters;
      }
      if (first == null || run.startedAt.isBefore(first)) {
        first = run.startedAt;
      }

      // Only runs long enough for pace to mean anything. A 200 m dash to catch
      // a bus would otherwise stand as a lifetime best forever.
      if (run.distanceMeters >= 1000) {
        final pace =
            run.avgPaceSecondsPerKm ??
            (run.duration.inSeconds / (run.distanceMeters / 1000));
        if (pace > 0 && (fastest == null || pace < fastest)) fastest = pace;
      }
    }

    return RunnerStats(
      runCount: runs.length,
      totalMeters: totalMeters,
      totalDuration: totalDuration,
      longestRunMeters: longest,
      fastestPaceSecondsPerKm: fastest,
      firstRunAt: first,
      currentStreakWeeks: _streakWeeks(runs, now ?? DateTime.now()),
    );
  }

  /// Counts back from the week of the most recent run while each week has one.
  ///
  /// Anchored to the last run rather than to today, so opening the app on a
  /// Monday having run on Sunday does not read as a broken streak — the runner
  /// has not missed anything yet.
  static int _streakWeeks(List<RunSummary> runs, DateTime now) {
    if (runs.isEmpty) return 0;

    final weeks = <DateTime>{for (final run in runs) _weekStart(run.startedAt)};
    var cursor = weeks.reduce((a, b) => a.isAfter(b) ? a : b);

    // **A streak that cannot lapse is not a streak.** Anchoring to the last run
    // is right for the Monday-after-a-Sunday-run case named above, and wrong
    // once the gap is real: a runner who last went out twenty days ago was
    // shown "4 wk" beside their coach saying "nothing recorded for 20 days".
    // Two numbers on one screen, disagreeing.
    //
    // One week of grace, which is what the anchoring was for. Past that the
    // run of weeks has ended, and the honest answer is none.
    final thisWeek = _weekStart(now);
    final lapsed = thisWeek.difference(cursor).inDays > 7;
    if (lapsed) return 0;

    var streak = 0;
    while (weeks.contains(cursor)) {
      streak++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 7);
    }
    return streak;
  }

  /// The Monday of a date's week, at midnight, so runs group by calendar week.
  static DateTime _weekStart(DateTime at) {
    final day = DateTime(at.year, at.month, at.day);
    return DateTime(day.year, day.month, day.day - (day.weekday - 1));
  }
}
