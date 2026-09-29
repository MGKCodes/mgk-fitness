import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/sync_status.dart';

/// Where backup stands — the one answer every surface reads.
enum BackupState {
  /// Nothing wrong. There may still be something waiting for the next
  /// checkpoint; [BackupStatus.pending] says.
  idle,

  /// A run is under way.
  running,

  /// No connection. It goes when there is one.
  offline,

  /// The server failed or timed out. Retried on its own.
  failed,

  /// Backup is misconfigured on the server. Retried, less often.
  unavailable,

  /// No account on this device.
  signedOut,

  /// Signed in, but the server no longer accepts the session.
  expired,
}

@immutable
class BackupStatus {
  const BackupStatus({
    this.state = BackupState.idle,
    this.pending = const SyncPending(workouts: 0, lastSyncedAt: null),
    this.retryAt,
    this.lastReport,
  });

  final BackupState state;
  final SyncPending pending;

  /// What the last run did — for "3 up, 1 down just now".
  final SyncReport? lastReport;

  /// When the next automatic try is due, after a failure.
  final DateTime? retryAt;

  /// Workouts the server refused, which wait on the lifter.
  bool get needsAttention => pending.rejected.isNotEmpty;

  bool isBackedUp(String id) => pending.isBackedUp(id);

  /// Whether this state can clear on its own — a retry is coming — as against
  /// one that waits on the lifter.
  bool get retrying =>
      state == BackupState.offline ||
      state == BackupState.failed ||
      state == BackupState.unavailable;

  BackupStatus copyWith({
    BackupState? state,
    SyncPending? pending,
    DateTime? Function()? retryAt,
  }) => BackupStatus(
    state: state ?? this.state,
    pending: pending ?? this.pending,
    retryAt: retryAt == null ? this.retryAt : retryAt(),
    lastReport: lastReport,
  );
}

/// What a screen further down needs from backup, as one thing to pass: the
/// live status, and the two things its messages can ask for.
@immutable
class BackupHooks {
  const BackupHooks({required this.status, this.onRetry, this.onSignIn});

  final ValueListenable<BackupStatus> status;
  final VoidCallback? onRetry;
  final VoidCallback? onSignIn;
}

/// **When backup runs** — at checkpoints, never on the path of a set.
///
/// It used to run on sign-in and from Settings, and nowhere else: a session
/// finished on Tuesday went up whenever somebody next opened Settings, and a
/// phone lost on Wednesday took it with it. Now the shell calls [checkpoint]
/// after Finish, after the library changes, on launch and on return to the
/// foreground, and [runNow] on sign-in and from *Sync now*.
///
/// A checkpoint waits [settle] before running, so a burst — Finish, then the
/// summary teaching the workout, then an Undo — is one run, not three. A run
/// that fails for a reason that can clear on its own is tried again at
/// [retries] — 30 s, 2 min, 10 min, then hourly while the app is open — which
/// is also how a connection coming back is noticed, since the app has no
/// connectivity listener.
class BackupScheduler {
  BackupScheduler({
    required Future<SyncReport> Function() run,
    required Future<SyncPending> Function() pending,
    this.settle = const Duration(seconds: 2),
    this.retries = const <Duration>[
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 10),
      Duration(hours: 1),
    ],
    DateTime Function()? clock,
  }) : _run = run,
       _pending = pending,
       _now = clock ?? DateTime.now;

  final Future<SyncReport> Function() _run;
  final Future<SyncPending> Function() _pending;
  final DateTime Function() _now;

  final Duration settle;
  final List<Duration> retries;

  /// Read by every surface that says anything about backup.
  ValueListenable<BackupStatus> get status => _status;
  final ValueNotifier<BackupStatus> _status = ValueNotifier<BackupStatus>(
    const BackupStatus(),
  );

  Timer? _settleTimer;
  Timer? _retryTimer;
  int _failures = 0;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  /// Something worth backing up happened. Runs once [settle] has passed with
  /// nothing further — however many arrive meanwhile.
  void checkpoint() {
    if (_disposed) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(settle, () => unawaited(_go()));
  }

  /// Runs now — a lifter asked, or just signed in. Returns the report, or
  /// null when a run was already under way (it will run again after).
  Future<SyncReport?> runNow() {
    _settleTimer?.cancel();
    return _go();
  }

  /// Re-reads what is waiting without running — after a change a surface
  /// wants shown before the next checkpoint fires.
  Future<void> refresh() async {
    final pending = await _pending();
    if (_disposed) return;
    _status.value = _status.value.copyWith(pending: pending);
  }

  Future<SyncReport?> _go() async {
    if (_disposed) return null;
    if (_running) {
      _again = true;
      return null;
    }
    _running = true;
    _retryTimer?.cancel();
    _status.value = _status.value.copyWith(
      state: BackupState.running,
      retryAt: () => null,
    );

    SyncReport report;
    try {
      report = await _run();
    } on Object catch (e) {
      // [BackupService.run] promises not to throw; this is the belt to that.
      report = SyncReport.unavailable('$e');
    }
    final pending = await _pending();
    _running = false;
    if (_disposed) return report;

    final state = _stateFor(report);
    DateTime? retryAt;
    if (state == BackupState.offline ||
        state == BackupState.failed ||
        state == BackupState.unavailable) {
      final wait = retries[_failures.clamp(0, retries.length - 1)];
      _failures++;
      retryAt = _now().add(wait);
      _retryTimer = Timer(wait, () => unawaited(_go()));
    } else {
      _failures = 0;
    }
    _status.value = BackupStatus(
      state: state,
      pending: pending,
      retryAt: retryAt,
      lastReport: report,
    );

    if (_again) {
      _again = false;
      checkpoint();
    }
    return report;
  }

  static BackupState _stateFor(SyncReport report) {
    if (report.outcome == SyncOutcome.signedOut) return BackupState.signedOut;
    if (!report.isFailure) return BackupState.idle;
    return switch (report.problem) {
      BackupProblem.offline => BackupState.offline,
      BackupProblem.expired => BackupState.expired,
      BackupProblem.signedOut => BackupState.signedOut,
      BackupProblem.unavailable => BackupState.unavailable,
      BackupProblem.server ||
      BackupProblem.rejected ||
      null => BackupState.failed,
    };
  }

  void dispose() {
    _disposed = true;
    _settleTimer?.cancel();
    _retryTimer?.cancel();
    _status.dispose();
  }
}
