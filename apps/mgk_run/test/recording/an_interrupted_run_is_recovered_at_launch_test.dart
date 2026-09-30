// Regression for EDGE-1: a run process death interrupts mid-way — an iOS
// memory kill, an Android task swipe, a reboot, a crash — sat on disk
// forever with `endedAt` null, its recovery marker, because nothing in
// `lib/` ever called `AppDatabase.activeRun()`. `DriftRunRepository.fetchRuns`
// filters null-`endedAt` rows out of the log on purpose, so the run was
// invisible everywhere: not in the log, not backed up, not recoverable on a
// later launch either. See the throwaway reproduction under
// .claude/worktrees/review-edge/apps/mgk_run/test/zz_edge_review/interrupted_run_is_lost_test.dart.
//
// `recoverInterruptedRun` is now called once at launch (`main.dart`), before
// anything reads the log.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/history/data/drift_run_repository.dart';
import 'package:mgk_run/src/features/recording/data/location_source.dart';
import 'package:mgk_run/src/features/recording/data/recording_run_recorder.dart';
import 'package:mgk_run/src/features/recording/data/run_recovery.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';

class _Source implements LocationSource {
  final StreamController<RunPoint> _c = StreamController<RunPoint>.broadcast();
  @override
  Stream<RunPoint> get fixes => _c.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  void emit(RunPoint p) => _c.add(p);
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('a run killed mid-way is recovered into the log, with the right '
      'distance and a note', () async {
    final source = _Source();
    final t0 = DateTime(2026, 9, 29, 7);
    final recorder = RecordingRunRecorder(
      source: source,
      db: db,
      newId: () => 'killed-run',
      now: () => t0,
    );
    await recorder.start();
    // 200 fixes, 10 m apart, one a second: ~2 km in 200 s.
    for (var i = 0; i < 200; i++) {
      source.emit(
        RunPoint(
          latitude: 51.5,
          longitude: -0.12 + i * 0.000144, // ~10 m at 51.5N
          accuracyMeters: 5,
          timestamp: t0.add(Duration(seconds: i)),
        ),
      );
    }
    await pumpEventQueue(times: 2000);
    // Process death: nothing gets to call stop().

    // Before this, the log is empty and the row is unfinished — exactly
    // the state the throwaway reproduction found.
    expect(await DriftRunRepository(db).fetchRuns(), isEmpty);
    expect((await db.runById('killed-run'))!.endedAt, isNull);

    await recoverInterruptedRun(db);

    final log = await DriftRunRepository(db).fetchRuns();
    expect(log, hasLength(1));
    final run = log.single;
    expect(run.id, 'killed-run');
    // 199 hops of ~10 m each (the first fix only anchors the trace); the
    // smoother trims a little off the raw sum, the same as it would at
    // stop().
    expect(run.distanceMeters, closeTo(1990, 20));
    expect(run.duration, const Duration(seconds: 199));
    // Carried by the log's read, so the summary can say so (board F7, test
    // sheet C21) rather than only Edit.
    expect(run.notes, kRecoveredRunNote);
    // The trace itself is untouched by recovery — still every fix that
    // ever landed (rule 1), same as `fetchRuns`' summary-only reads.
    expect(await db.pointsForRun('killed-run'), hasLength(200));

    final row = await db.runById('killed-run');
    expect(row!.endedAt, t0.add(const Duration(seconds: 199)));
    expect(row.notes, kRecoveredRunNote);

    // A second launch finds nothing left to recover.
    expect(await db.activeRun(), isNull);
    await recoverInterruptedRun(db); // must not throw or duplicate
    expect(await DriftRunRepository(db).fetchRuns(), hasLength(1));
  });

  test(
    'a run killed before any fix arrived is deleted, not shown as 0.00 km',
    () async {
      final source = _Source();
      final recorder = RecordingRunRecorder(
        source: source,
        db: db,
        newId: () => 'pointless-run',
        now: () => DateTime(2026, 9, 29, 7),
      );
      await recorder.start();
      // No fixes at all — killed in the first second, or stuck behind a
      // permission prompt.

      await recoverInterruptedRun(db);

      expect(await db.runById('pointless-run'), isNull);
      expect(await DriftRunRepository(db).fetchRuns(), isEmpty);
    },
  );

  test(
    'a recovered duration excludes a pause still open when the process died',
    () async {
      final source = _Source();
      var clock = DateTime(2026, 9, 29, 7);
      final recorder = RecordingRunRecorder(
        source: source,
        db: db,
        newId: () => 'paused-run',
        now: () => clock,
      );
      await recorder.start();
      for (var i = 0; i < 10; i++) {
        source.emit(
          RunPoint(
            latitude: 51.5,
            longitude: -0.12 + i * 0.000144,
            accuracyMeters: 5,
            timestamp: clock.add(Duration(seconds: i)),
          ),
        );
      }
      await pumpEventQueue(times: 200);
      // 9 seconds of running (10 fixes, t=0..9), then a pause that is still
      // open when the process dies 5 minutes later — no `stop()`, no
      // `resume()`.
      clock = clock.add(const Duration(seconds: 9));
      await recorder.pause();
      clock = clock.add(const Duration(minutes: 5));

      await recoverInterruptedRun(db);

      final run = (await DriftRunRepository(db).fetchRuns()).single;
      // Duration is measured to the last fix (t=9s), and the recorder's own
      // startedAt..lastFix span is already exactly the 9 seconds that were
      // ever running — the open pause after it contributes nothing because
      // no fix arrived during it for `endedAt` to reach.
      expect(run.duration, const Duration(seconds: 9));
    },
  );
}
