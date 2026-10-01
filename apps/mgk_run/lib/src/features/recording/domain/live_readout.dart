import 'package:flutter/foundation.dart';

/// What the lock screen is told about a run in progress.
///
/// Already in the runner's own words: the distance and the pace arrive as the
/// strings the in-run screen would show, in the runner's unit. The platform
/// side draws them and decides nothing.
@immutable
class LiveRunStatus {
  const LiveRunStatus({
    required this.distance,
    required this.pace,
    required this.elapsed,
    required this.paused,
  });

  /// "5.02 km".
  final String distance;

  /// "5:31 /km", or dashes while there is no honest pace to give.
  final String pace;

  /// Time on the run's clock. The platform counts on from here by itself, so
  /// the time moves every second while the rest is refreshed every few.
  final Duration elapsed;

  /// Whether the runner has paused. The clock stands still while they have.
  final bool paused;

  @override
  bool operator ==(Object other) =>
      other is LiveRunStatus &&
      other.distance == distance &&
      other.pace == pace &&
      other.elapsed == elapsed &&
      other.paused == paused;

  @override
  int get hashCode => Object.hash(distance, pace, elapsed, paused);
}

/// The run's figures, somewhere they can be read without unlocking the phone.
///
/// **A phone in an armband is a phone that is locked.** The in-run screen had
/// the distance, the time and the pace, and all three were behind a passcode
/// for the whole of every run. Asked for at the first look at build 28.
///
/// On the iPhone this is a Live Activity, on the lock screen and in the
/// Dynamic Island. On Android it is a notification the app keeps up to date.
/// Anywhere else it is nothing.
///
/// **Never the reason a run fails.** Every method swallows what goes wrong:
/// a runner who has switched Live Activities off, refused notifications, or
/// is on a phone too old for either still records a run, exactly as before.
abstract interface class LiveRunReadout {
  /// Before a run, while the runner is still looking at the screen: whatever
  /// the platform wants asked first. On Android 13 and later that is the
  /// permission to post a notification, asked once.
  Future<void> prepare();

  /// Shows [status], or updates what is showing.
  Future<void> show(LiveRunStatus status);

  /// Takes it down. Safe to call when nothing is showing.
  Future<void> end();
}
