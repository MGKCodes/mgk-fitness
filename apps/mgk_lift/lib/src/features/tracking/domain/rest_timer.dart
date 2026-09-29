import 'package:meta/meta.dart';

/// The rest between two sets.
///
/// **Derived from a timestamp, never from a tick count.** The obvious
/// implementation counts down on a `Timer.periodic` and decrements a field, and
/// it is wrong for the one situation this exists for: the lifter puts the phone
/// in their pocket. Timers are throttled or stopped outright when an app is
/// backgrounded, so a counter comes back reading whatever it happened to reach
/// before Android suspended it. Storing when rest *started* and subtracting from
/// the wall clock means the answer is right whether the screen was watched or
/// not — the ticker only decides how often it is redrawn.
///
/// Immutable, so extending rest produces a new one and a widget can never hold a
/// timer that has moved underneath it.
@immutable
class RestTimer {
  const RestTimer({required this.startedAt, required this.duration});

  final DateTime startedAt;
  final Duration duration;

  /// The default rest, when nothing else says otherwise.
  ///
  /// 90 seconds is the compromise: too short for a heavy triple, too long for
  /// curls, and about right for the accessory work most of a session is made of.
  /// It is a starting point to adjust from, not a recommendation.
  static const Duration defaultRest = Duration(seconds: 90);

  /// How much rest is left, floored at zero. Never negative — "minus twelve
  /// seconds" is not a thing a lifter needs to be told.
  Duration remainingAt(DateTime now) {
    final left = duration - now.difference(startedAt);
    return left.isNegative ? Duration.zero : left;
  }

  bool isDoneAt(DateTime now) => remainingAt(now) == Duration.zero;

  /// When this rest runs out. Fixed at the start and moved only by an
  /// adjustment, which is what the background alert is scheduled against.
  DateTime get endsAt => startedAt.add(duration);

  /// How long past the end this rest has run — zero until it is over.
  ///
  /// Shown as `+0:40` once rest is done, because the honest number after a
  /// timer runs out is how long the lifter actually rested. Two of the apps
  /// the 2026-09-29 research liked best keep counting; a timer frozen at
  /// 0:00 says nothing about a set started four minutes late.
  Duration overtimeAt(DateTime now) {
    final over = now.difference(endsAt);
    return over.isNegative ? Duration.zero : over;
  }

  /// 0 at the start, 1 when rest is over. For the progress line.
  double progressAt(DateTime now) {
    if (duration.inMilliseconds <= 0) return 1;
    final elapsed = now.difference(startedAt).inMilliseconds;
    return (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Adds to the rest, or takes away — [by] may be negative.
  ///
  /// Shortening cannot take the total below what has already been rested, so
  /// pressing −30s twice ends the rest rather than reviving a timer that has
  /// already finished. It also cannot go below zero.
  RestTimer extendedBy(Duration by, DateTime now) {
    final elapsed = now.difference(startedAt);
    var next = duration + by;
    if (next.isNegative) next = Duration.zero;
    if (by.isNegative && next < elapsed) next = elapsed;
    return RestTimer(startedAt: startedAt, duration: next);
  }

  /// `1:30`, or `0:07`. Minutes and seconds throughout — rest is never long
  /// enough for hours to be worth the column.
  static String format(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
