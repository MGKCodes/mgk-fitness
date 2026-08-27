import '../../recording/domain/best_effort.dart';
import '../../recording/domain/run_summary.dart';

/// Lifetime totals and bests, derived from the runs on the device.
///
/// Derived rather than stored: the runs are the source of truth, so a total that
/// disagreed with them would be a bug waiting to happen. Recomputing a few
/// hundred rows is free next to keeping a second copy honest.
///
/// **[bestEfforts] is the one figure here whose ingredients are stored**, and
/// the exception proves the rule rather than breaking it. A record is the
/// fastest continuous stretch of a distance *inside* a run, which is a walk
/// over thousands of trace points; that walk happens once, when the run
/// finishes (ADR-0026). What is folded here is still only the runs — four
/// numbers each, already on the row — so this class keeps deriving rather than
/// caching.
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
    this.bestEfforts = const <double, Duration>{},
    this.averageEfforts = const <double, Duration>{},
    this.hasRecordlessRuns = false,
  });

  final int runCount;
  final double totalMeters;
  final Duration totalDuration;
  final double? longestRunMeters;
  final double? fastestPaceSecondsPerKm;
  final DateTime? firstRunAt;

  /// The fastest each standard distance has ever been covered, keyed by the
  /// distance in metres — 5000, 10000, 21097.5, 42195.
  ///
  /// A distance with no entry has never been run, and there is no key for it
  /// rather than a null against it. Read with [bestEffortAt], which is the only
  /// place the exactness of a `double` key matters: every value in here came
  /// from `kRecordDistancesMeters`, so the keys and the lookups are literally
  /// the same constants.
  final Map<double, Duration> bestEfforts;

  /// What each standard distance **usually** takes, keyed the same way as
  /// [bestEfforts] — the mean of every qualifying stretch in the log, not the
  /// quickest one.
  ///
  /// **A best is a worse answer to the question this page is asked.** A runner
  /// looking at their own 5K wants to know what they run, and a lifetime best
  /// is by construction the one day that was not typical — it is a single
  /// sample, it never moves except downwards, and for most runners it was set
  /// once and is now a number they cannot repeat. An average moves with the
  /// training, which is the whole thing this app is for.
  ///
  /// The bests are still computed and still kept; they belong on a view that is
  /// about records rather than in the row that says what a 5K is.
  final Map<double, Duration> averageEfforts;

  /// True when the log holds at least one run long enough to have set a record
  /// that set none.
  ///
  /// **The only reason the records table can look wrong to a runner who knows
  /// what they ran.** Somebody who types their marathon in by hand has a
  /// marathon in their log and a dash beside "Marathon", because a hand-entered
  /// run has no trace and a record is read off the trace (ADR-0026). So is
  /// somebody whose GPS dropped for a minute in the middle of a 10 km, leaving
  /// no continuous 10 km in the file. Both are correct and neither is
  /// self-evident, so the page says so instead of leaving them to guess.
  ///
  /// False for a runner whose records are all present or who has never run far
  /// enough to hold one — nothing to explain, so nothing said.
  final bool hasRecordlessRuns;

  /// Consecutive weeks, counting back from the most recent run's week, that
  /// contain at least one run.
  final int currentStreakWeeks;

  /// The lifetime best at [meters], or null if that distance has never been
  /// covered inside a run.
  Duration? bestEffortAt(double meters) => bestEfforts[meters];

  /// What [meters] usually takes, or null if it has never been covered.
  Duration? averageEffortAt(double meters) => averageEfforts[meters];

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
    final bests = <double, Duration>{};
    final effortTotals = <double, int>{};
    final effortCounts = <double, int>{};
    var recordless = false;

    // The shortest distance a record is kept at. A run under it was never going
    // to set one, so its silence is not the silence worth explaining.
    final shortestRecord = kRecordDistancesMeters.reduce(
      (a, b) => a < b ? a : b,
    );

    for (final run in runs) {
      totalMeters += run.distanceMeters;
      totalDuration += run.duration;

      for (final effort in run.bestEfforts) {
        final standing = bests[effort.distanceMeters];
        if (standing == null || effort.duration < standing) {
          bests[effort.distanceMeters] = effort.duration;
        }
        // Summed in microseconds rather than by folding `Duration`s, so the
        // mean is one division at the end instead of a running average that
        // drifts by a tick per run.
        effortTotals[effort.distanceMeters] =
            (effortTotals[effort.distanceMeters] ?? 0) +
            effort.duration.inMicroseconds;
        effortCounts[effort.distanceMeters] =
            (effortCounts[effort.distanceMeters] ?? 0) + 1;
      }
      // Long enough to have held a record, and holding none. Judged on the
      // run's own distance rather than on its trace, because the log's read
      // does not carry traces — and because this is the runner's question:
      // "I ran 10 km, where is my 10K?"
      if (run.bestEfforts.isEmpty && run.distanceMeters >= shortestRecord) {
        recordless = true;
      }

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
      bestEfforts: Map<double, Duration>.unmodifiable(bests),
      averageEfforts: Map<double, Duration>.unmodifiable(<double, Duration>{
        for (final MapEntry<double, int> entry in effortTotals.entries)
          entry.key: Duration(
            microseconds: entry.value ~/ effortCounts[entry.key]!,
          ),
      }),
      hasRecordlessRuns: recordless,
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
