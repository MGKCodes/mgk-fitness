import 'dart:math' as math;

import '../../recording/domain/run_summary.dart';
import 'plan_shape.dart';
import 'prescribed_distance.dart';
import 'runner_profile.dart';

/// Whether a runner could cover their goal distance today.
///
/// **The point of a horizon plan.** A block counts down to a date; a horizon has
/// none, so without this it counts nothing and never arrives anywhere. The
/// moment it exists for is the coach saying *you could run this now — want to
/// find a race?*, which is also the moment a horizon becomes a block.
///
/// Deterministic, like every other number the coach is handed. A model asked
/// "am I ready for a marathon?" will answer warmly and confidently either way,
/// and being wrong in the encouraging direction is how someone gets hurt.
class Readiness {
  const Readiness({
    required this.fraction,
    required this.longestNeededMeters,
    required this.weeklyNeededMeters,
  });

  /// How far along, 0 to 1. Reaches 1 only when both halves are satisfied.
  final double fraction;

  /// The longest single run the goal asks for.
  final double longestNeededMeters;

  /// The weekly volume the goal asks for.
  final double weeklyNeededMeters;

  /// Ready when the long run *and* the weekly volume are there.
  ///
  /// Both, not an average: someone who has run 32 km once off 20 km weeks has
  /// a long run and no engine, and the average would call them ready.
  bool get isReady => fraction >= 1;

  /// Plain words, because "0.62" is not something to tell a runner.
  ///
  /// Deliberately none of them repeat "building toward", which is what the
  /// headline above already says — "Building toward a marathon · building
  /// toward it" is one line saying the same thing twice.
  String get summary => switch (fraction) {
    >= 1 => 'ready for it now',
    >= 0.85 => 'nearly there',
    >= 0.6 => 'well on the way',
    >= 0.35 => 'about halfway',
    >= 0.15 => 'getting started',
    _ => 'early days',
  };
}

/// The longest run a goal asks for, as a fraction of the goal.
///
/// Shorter races want you to have covered the distance; longer ones do not. A
/// 10 km runner should have run 10 km, a marathon runner should not have run a
/// marathon in training — the taper and the day carry the last stretch. The
/// curve runs from 1.0 at 10 km to about 0.75 at the marathon.
double _longestNeeded(double goalMeters) {
  if (goalMeters <= 10000) return goalMeters;
  final fraction = (1.0 - (goalMeters - 10000) / 130000).clamp(0.75, 1.0);
  return goalMeters * fraction;
}

/// What the runner can currently do over one run.
///
/// Read from the **run log** first, falling back to what they told us at
/// intake. A profile ages: someone who said "12 km" three months ago and has
/// since run 25 km is ready on the evidence, and asking them to re-state it
/// would be the app ignoring what it already knows.
double _longestAchieved(
  RunnerProfile profile,
  List<RunSummary> runs,
  DateTime now,
) {
  final since = now.subtract(readinessWindow);
  var longest = profile.longestRecentMeters;
  for (final run in runs) {
    if (run.startedAt.isBefore(since) || run.startedAt.isAfter(now)) continue;
    longest = math.max(longest, run.distanceMeters);
  }
  return longest;
}

/// How far back the run log counts toward readiness. Twelve weeks: long enough
/// that a build shows, short enough that last winter's fitness does not.
const Duration readinessWindow = Duration(days: 84);

/// Assesses [profile] against its own goal.
///
/// Returns null when there is no goal to be ready for — a rhythm or a log.
Readiness? assessReadiness(
  RunnerProfile profile,
  List<RunSummary> runs, {
  required DateTime now,
}) {
  final goal = profile.goalDistanceMeters;
  if (goal == null || !shapeOf(profile).progresses) return null;

  final longestNeeded = _longestNeeded(goal);
  // Weekly volume is scaled off the long run rather than off the goal: the long
  // run is already the goal adjusted for distance, and a week that cannot
  // support twice its longest run is a week built around one heroic day.
  final weeklyNeeded = longestNeeded * 2;

  final longest = (_longestAchieved(profile, runs, now) / longestNeeded).clamp(
    0.0,
    1.0,
  );
  final weekly = (profile.currentWeeklyMeters / weeklyNeeded).clamp(0.0, 1.0);

  return Readiness(
    // The lower of the two, not the average. Being ready means both are there,
    // and averaging lets one enormous run stand in for training.
    fraction: math.min(longest, weekly),
    longestNeededMeters: longestNeeded,
    weeklyNeededMeters: weeklyNeeded,
  );
}

/// What the coach should say about being ready, or null when there is nothing
/// worth saying yet.
///
/// Only speaks up at the end. A progress bar toward a distance is the runner's
/// business every week; "you could do this now" is worth interrupting for once.
String? readinessNote(Readiness readiness, double goalMeters) {
  if (readiness.isReady) {
    final name = raceName(goalMeters);
    return name == null
        ? 'You could cover this distance now. Worth finding something to '
              'aim at?'
        : 'You could run a ${name.toLowerCase()} now. Worth finding one to '
              'enter?';
  }
  return null;
}
