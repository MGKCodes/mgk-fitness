import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/sync/domain/sync_status.dart';
import 'package:mgk_lift/src/features/sync/presentation/backup_scheduler.dart';

/// When backup runs. Driven on the test clock: a checkpoint settles for two
/// seconds, and a failure retries at 30 s, 2 min, 10 min, then hourly.
void main() {
  late int runs;
  late List<SyncReport> results;
  late SyncPending pending;
  Completer<void>? hold;

  setUp(() {
    runs = 0;
    results = <SyncReport>[];
    pending = const SyncPending(workouts: 0, lastSyncedAt: null);
    hold = null;
  });

  BackupScheduler scheduler() => BackupScheduler(
    run: () async {
      runs++;
      if (hold != null) await hold!.future;
      return results.isEmpty
          ? const SyncReport(outcome: SyncOutcome.upToDate)
          : results.removeAt(0);
    },
    pending: () async => pending,
  );

  const offline = SyncReport.unavailable(
    'socket',
    problem: BackupProblem.offline,
  );

  testWidgets('a burst of checkpoints is one run, once it settles', (
    tester,
  ) async {
    final s = scheduler();
    addTearDown(s.dispose);

    s
      ..checkpoint()
      ..checkpoint();
    await tester.pump(const Duration(seconds: 1));
    s.checkpoint();
    await tester.pump(const Duration(seconds: 1));
    expect(runs, 0, reason: 'still settling');

    await tester.pump(const Duration(seconds: 1));
    expect(runs, 1);
    expect(s.status.value.state, BackupState.idle);
  });

  testWidgets('a failure that can clear retries on the schedule', (
    tester,
  ) async {
    final s = scheduler();
    addTearDown(s.dispose);
    results = <SyncReport>[offline, offline, offline, offline, offline];

    await s.runNow();
    await tester.pump();
    expect(s.status.value.state, BackupState.offline);
    expect(s.status.value.retryAt, isNotNull);

    for (final (wait, total) in <(Duration, int)>[
      (const Duration(seconds: 30), 2),
      (const Duration(minutes: 2), 3),
      (const Duration(minutes: 10), 4),
      (const Duration(hours: 1), 5),
      (const Duration(hours: 1), 6),
    ]) {
      await tester.pump(wait - const Duration(seconds: 1));
      expect(runs, total - 1, reason: 'not before $wait');
      await tester.pump(const Duration(seconds: 1));
      expect(runs, total, reason: 'at $wait');
    }
  });

  testWidgets('a success resets the schedule', (tester) async {
    final s = scheduler();
    addTearDown(s.dispose);
    results = <SyncReport>[
      offline,
      const SyncReport(outcome: SyncOutcome.synced, pushed: 1),
      offline,
    ];

    await s.runNow();
    await tester.pump(const Duration(seconds: 30));
    expect(runs, 2);
    expect(s.status.value.state, BackupState.idle);
    expect(s.status.value.retryAt, isNull);

    await s.runNow();
    await tester.pump(const Duration(seconds: 30));
    expect(runs, 4, reason: 'back to 30 s after the success, not 2 min');
  });

  testWidgets('what waits on the lifter is not retried', (tester) async {
    final s = scheduler();
    addTearDown(s.dispose);
    results = <SyncReport>[
      const SyncReport.signedOut(),
      const SyncReport.unavailable('jwt', problem: BackupProblem.expired),
    ];

    await s.runNow();
    await tester.pump(const Duration(hours: 2));
    expect(s.status.value.state, BackupState.signedOut);
    expect(runs, 1);

    await s.runNow();
    await tester.pump(const Duration(hours: 2));
    expect(s.status.value.state, BackupState.expired);
    expect(runs, 2);
  });

  testWidgets('a refusal is not a failure: the run succeeded', (tester) async {
    final s = scheduler();
    addTearDown(s.dispose);
    results = <SyncReport>[
      const SyncReport(outcome: SyncOutcome.synced, pushed: 2, rejected: 1),
    ];
    pending = const SyncPending(
      workouts: 0,
      lastSyncedAt: null,
      rejected: <RejectedWorkout>[
        RejectedWorkout(
          id: 'w',
          name: 'Push',
          isTemplate: false,
          detail: '22003: x',
        ),
      ],
    );

    await s.runNow();
    await tester.pump(const Duration(hours: 1));

    expect(runs, 1, reason: 'a refused workout waits for an edit');
    expect(s.status.value.state, BackupState.idle);
    expect(s.status.value.needsAttention, isTrue);
  });

  testWidgets('a checkpoint during a run runs again after it', (tester) async {
    final s = scheduler();
    addTearDown(s.dispose);
    hold = Completer<void>();

    final first = s.runNow();
    await tester.pump();
    expect(s.status.value.state, BackupState.running);

    // Finish lands while a run is already going — its session was not in it.
    expect(await s.runNow(), isNull, reason: 'no second run in parallel');
    s.checkpoint();
    hold!.complete();
    hold = null;
    await first;
    await tester.pump(const Duration(seconds: 2));

    expect(runs, 2);
  });

  testWidgets('nothing runs after it is disposed', (tester) async {
    final s = scheduler();
    results = <SyncReport>[offline];
    await s.runNow();
    s
      ..checkpoint()
      ..dispose();
    await tester.pump(const Duration(hours: 2));
    expect(runs, 1);
  });
}
