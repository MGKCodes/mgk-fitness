/// A buzz when rest is over, **with the phone locked or the app in the
/// background** — the one moment the screen's own haptic cannot reach.
///
/// Every lifting app worth comparing against does this, and "a timer I cannot
/// trust" is the commonest complaint about all of them (research, 2026-09-29):
/// a lifter pockets the phone between sets, and a timer that only buzzes while
/// it is being looked at is a timer that makes them look.
///
/// The screen schedules one alert when the app leaves the foreground with a
/// rest running, at the rest's fixed end time, and cancels it when the app
/// comes back. So in the foreground there is exactly one buzz (the screen's)
/// and in the background exactly one (the system's), never both.
abstract interface class RestAlerts {
  /// Whether an alert can be shown at all: the lifter has allowed
  /// notifications. False until asked on iOS and on Android 13 and later.
  Future<bool> allowed();

  /// Whether the lifter has been asked before, by this app. Asking twice is
  /// nagging; a lifter who said no meant it, and Settings is where they change
  /// their mind.
  Future<bool> asked();

  /// Records that the lifter has been offered alerts, without prompting. The
  /// offer is a toast they can let go by; letting it go is an answer too.
  Future<void> markAsked();

  /// Shows the system's permission prompt. Returns whether it was granted.
  Future<bool> ask();

  /// Schedules the alert for [at], replacing any already scheduled.
  Future<void> schedule({
    required DateTime at,
    required String title,
    required String body,
  });

  /// Withdraws the scheduled alert, if there is one.
  Future<void> cancel();
}

/// A scripted [RestAlerts] for tests and the preview.
class FakeRestAlerts implements RestAlerts {
  FakeRestAlerts({this.isAllowed = true, this.wasAsked = true});

  bool isAllowed;
  bool wasAsked;

  /// What is scheduled now, if anything.
  DateTime? scheduledAt;
  String? scheduledBody;

  /// Every schedule and cancel, in order, for asserting the lifecycle.
  final List<String> calls = <String>[];

  @override
  Future<bool> allowed() async => isAllowed;

  @override
  Future<bool> asked() async => wasAsked;

  @override
  Future<void> markAsked() async => wasAsked = true;

  @override
  Future<bool> ask() async {
    wasAsked = true;
    calls.add('ask');
    return isAllowed;
  }

  @override
  Future<void> schedule({
    required DateTime at,
    required String title,
    required String body,
  }) async {
    scheduledAt = at;
    scheduledBody = body;
    calls.add('schedule');
  }

  @override
  Future<void> cancel() async {
    scheduledAt = null;
    scheduledBody = null;
    calls.add('cancel');
  }
}
