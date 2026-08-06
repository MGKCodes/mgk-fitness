import 'package:meta/meta.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../tracking/domain/session.dart';

/// What a lifter has actually done, derived from their log.
///
/// **Computed in Dart over sessions, not in SQL.** Liftio had ~40 query
/// functions each embedding its own aggregate, which meant the rules about what
/// counts — is a warm-up in the volume? does an unticked set count? — lived in
/// forty places and had to agree by hand. Here they live once, in
/// [Session.workingSets], and every figure folds over that.
///
/// It also makes them testable without a database, which is why the streak bug
/// below could be found at all.
@immutable
class TrainingStats {
  const TrainingStats._({
    required this.sessions,
    required this.totalVolume,
    required this.totalSets,
    required this.totalTime,
    required this.currentWeekStreak,
    required this.longestWeekStreak,
    required this.sessionsPerWeek,
  });

  /// Folds a log into every headline figure in one pass.
  ///
  /// [now] is injected rather than read, because a streak that depends on the
  /// wall clock is otherwise untestable.
  factory TrainingStats.from(List<Session> log, {required DateTime now}) {
    final finished = log.where((s) => !s.isInProgress).toList();

    var volume = Mass.zero;
    var sets = 0;
    var time = Duration.zero;
    for (final session in finished) {
      time += session.elapsedAt(now);
      for (final set in session.workingSets) {
        sets++;
        volume += Mass.kilograms(set.weightKg) * set.reps;
      }
    }

    final weeks = <DateTime>{
      for (final s in finished) startOfWeek(s.startedAt),
    };

    return TrainingStats._(
      sessions: finished.length,
      totalVolume: volume,
      totalSets: sets,
      totalTime: time,
      currentWeekStreak: _currentStreak(weeks, now),
      longestWeekStreak: _longestStreak(weeks),
      sessionsPerWeek: _perWeek(finished, now),
    );
  }

  final int sessions;
  final Mass totalVolume;
  final int totalSets;
  final Duration totalTime;

  /// Consecutive weeks trained, counting back from this one.
  ///
  /// This week not being trained *yet* does not break it — it is Tuesday for
  /// somebody. The streak only breaks once a whole week goes by empty.
  final int currentWeekStreak;

  final int longestWeekStreak;
  final double sessionsPerWeek;

  /// The best estimated one-rep max for a movement, and the set that produced
  /// it. Null when nothing qualifying has been lifted.
  static OneRepMax? bestOneRepMax(List<Session> log, String exerciseName) {
    OneRepMax? best;
    for (final session in log.where((s) => !s.isInProgress)) {
      for (final exercise in session.exercises) {
        if (exercise.name.toLowerCase() != exerciseName.toLowerCase()) continue;
        for (final set in exercise.workingSets) {
          final estimate = estimateOneRepMax(
            Mass.kilograms(set.weightKg),
            set.reps,
          );
          if (estimate == null) continue;
          if (best == null || estimate.kilograms > best.estimate.kilograms) {
            best = OneRepMax(
              estimate: estimate,
              weight: Mass.kilograms(set.weightKg),
              reps: set.reps,
              on: session.startedAt,
            );
          }
        }
      }
    }
    return best;
  }

  /// Epley: `weight × (1 + reps / 30)`.
  ///
  /// Returns null above 12 reps rather than a number. Epley is a straight line
  /// fitted to low-rep work and drifts badly beyond it — at 30 reps it claims a
  /// double, which is not an estimate, it is an invention. Liftio capped at 30;
  /// this is stricter because a confidently wrong PB is worse than no PB.
  static Mass? estimateOneRepMax(Mass weight, int reps) {
    if (reps < 1 || reps > 12 || weight.kilograms <= 0) return null;
    if (reps == 1) return weight;
    return Mass.kilograms(weight.kilograms * (1 + reps / 30));
  }

  /// How often each movement appears, most-trained first.
  static List<ExerciseCount> byFrequency(List<Session> log) {
    final counts = <String, int>{};
    for (final session in log.where((s) => !s.isInProgress)) {
      for (final name in session.exercises.map((e) => e.name).toSet()) {
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }
    final rows = counts.entries
        .map((e) => ExerciseCount(name: e.key, sessions: e.value))
        .toList();
    rows.sort((a, b) {
      final c = b.sessions.compareTo(a.sessions);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return rows;
  }

  /// The Monday 00:00 of the week containing [date], in local time.
  ///
  /// **This is the fix for a real bug.** Liftio bucketed weeks with
  /// `floor(timestamp / msPerWeek)` — weeks counted from the Unix epoch, which
  /// was a *Thursday*. Its "weeks" therefore ran Thursday to Wednesday in UTC:
  /// training on a Monday and the following Sunday could count as two streak
  /// weeks, and a Wednesday/Thursday pair split one week into two.
  ///
  /// Local time, not UTC, for the same reason: a Sunday-evening session in
  /// Britain in summer is Monday in UTC, and would land in the wrong week.
  static DateTime startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  // Session.workingSets is the single definition of what counts. It used to
  // be restated here, and the two drifted: the session header counted warm-ups
  // in its volume while this did not, so the same lifter saw two different
  // totals depending which screen they were on.

  static int _currentStreak(Set<DateTime> weeks, DateTime now) {
    if (weeks.isEmpty) return 0;
    var week = startOfWeek(now);
    // Nothing this week yet is not a broken streak — it is Tuesday for
    // somebody. Step back one week before giving up.
    if (!weeks.contains(week)) {
      week = week.subtract(const Duration(days: 7));
    }
    var streak = 0;
    while (weeks.contains(week)) {
      streak++;
      week = week.subtract(const Duration(days: 7));
    }
    return streak;
  }

  static int _longestStreak(Set<DateTime> weeks) {
    if (weeks.isEmpty) return 0;
    final sorted = weeks.toList()..sort();
    var longest = 1;
    var current = 1;
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].difference(sorted[i - 1]).inDays;
      // Days rather than an index, so a DST week (167 or 169 hours) is still
      // one week apart.
      if (gap >= 6 && gap <= 8) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 1;
      }
    }
    return longest;
  }

  static double _perWeek(List<Session> finished, DateTime now) {
    if (finished.isEmpty) return 0;
    final first = finished
        .map((s) => s.startedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final spanDays = now.difference(first).inDays.abs();
    // A first week in progress is still a week — dividing by a fraction of one
    // would report someone who trained twice on day one as training 14 times a
    // week.
    final weeks = (spanDays / 7).clamp(1.0, double.infinity);
    return finished.length / weeks;
  }
}

/// A best estimated one-rep max, and what produced it.
@immutable
class OneRepMax {
  const OneRepMax({
    required this.estimate,
    required this.weight,
    required this.reps,
    required this.on,
  });

  final Mass estimate;
  final Mass weight;
  final int reps;
  final DateTime on;
}

/// How many sessions a movement appears in.
@immutable
class ExerciseCount {
  const ExerciseCount({required this.name, required this.sessions});

  final String name;
  final int sessions;
}
