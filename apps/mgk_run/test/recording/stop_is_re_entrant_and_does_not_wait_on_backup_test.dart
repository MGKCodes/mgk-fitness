// Regression for EDGE-6: `stop()` had no busy guard on the screen side and
// no re-entrancy guard of its own — it never cleared `_runId`, so a second
// call (concurrent, or simply after the first had already finished) read a
// run still in progress and reran the whole finalize sequence, including a
// second backup push. It also awaited that push before returning, so the
// Finish button stayed live for as long as a possibly-large trace took to
// upload — long enough on a marathon over a slow connection that a second
// tap looked, correctly, like nothing had happened yet. See the throwaway
// reproductions under
// .claude/worktrees/review-edge/apps/mgk_run/test/zz_edge_review/double_finish_test.dart
// and long_run_cost_test.dart. The screen-side busy guard has its own
// coverage in recording_screen_test.dart.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/history/data/run_backup.dart';
import 'package:mgk_run/src/features/recording/data/location_source.dart';
import 'package:mgk_run/src/features/recording/data/recording_run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';

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

/// Counts pushes and never completes one until told to — the stand-in for a
/// slow upload, so a test can prove `stop()` does not wait on it.
class _StuckBackup implements RunBackup {
  int pushRunCalls = 0;
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<bool> pushRun(String runId) async {
    pushRunCalls++;
    await _gate.future;
    return true;
  }

  @override
  Future<void> pushTrace(String runId) async {}

  @override
  Future<void> deleteRun(String runId) async {}

  @override
  Future<int> backfill() async => 0;
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<RecordingRunRecorder> aStartedRecorder(
    RunBackup backup,
    DateTime clock,
  ) async {
    final source = _Source();
    final recorder = RecordingRunRecorder(
      source: source,
      db: db,
      backup: backup,
      newId: () => 'r',
      now: () => clock,
    );
    await recorder.start();
    source.emit(
      RunPoint(
        latitude: 51.5,
        longitude: -0.12,
        accuracyMeters: 5,
        timestamp: clock,
      ),
    );
    await pumpEventQueue();
    return recorder;
  }

  test('stop() returns once the run is safe locally, without waiting for a '
      'stuck backup push', () async {
    final backup = _StuckBackup();
    final recorder = await aStartedRecorder(backup, DateTime(2026, 9, 29, 7));

    var stopped = false;
    final stopFuture = recorder.stop().then((_) => stopped = true);
    await pumpEventQueue();

    // Reached — proving the push was attempted at all — but deliberately
    // stuck, and stop() has already returned regardless.
    expect(backup.pushRunCalls, 1);
    expect(stopped, isTrue);
    expect(recorder.status, RecorderStatus.stopped);

    backup.release();
    await stopFuture;
  });

  test(
    'two stop() calls issued back to back share one finalize and one push',
    () async {
      final backup = _StuckBackup();
      final recorder = await aStartedRecorder(backup, DateTime(2026, 9, 29, 7));

      final first = recorder.stop();
      final second = recorder.stop();
      // The second call arrived before the first had a chance to clear
      // anything, and got hold of the exact same in-flight work rather than
      // starting its own.
      expect(identical(first, second), isTrue);

      backup.release();
      await Future.wait(<Future<void>>[first, second]);
      expect(backup.pushRunCalls, 1);
    },
  );

  test('stop() called again after the run has already finished is a safe '
      'no-op, not a second finalize', () async {
    final backup = _StuckBackup();
    final recorder = await aStartedRecorder(backup, DateTime(2026, 9, 29, 7));

    backup.release(); // let the first stop's push complete on its own
    await recorder.stop();
    expect(backup.pushRunCalls, 1);

    // The button-level busy guard is what stops this in the app; this
    // proves the recorder itself would not make it expensive or wrong if
    // something ever got past that guard.
    await recorder.stop();
    expect(backup.pushRunCalls, 1);
  });
}
