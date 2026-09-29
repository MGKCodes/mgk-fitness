// Regression for EDGE-8: a permission error arriving mid-run, followed by
// the runner pausing and then tapping "Allow location"
// (RecordingScreen._askAgain -> recorder.start()), used to start a brand new
// run over the paused one — start() guarded only against `recording`, so
// calling it from `paused` fell through to the fresh-start path: a new id, a
// new row, the clock reset to zero, and a second subscription to the same
// broadcast fixes stream so every fix landed twice. See the throwaway
// reproduction under
// .claude/worktrees/review-edge/apps/mgk_run/test/zz_edge_review/allow_location_restarts_run_test.dart.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/history/data/drift_run_repository.dart';
import 'package:mgk_run/src/features/recording/data/location_source.dart';
import 'package:mgk_run/src/features/recording/data/recording_run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';

class _Source implements LocationSource {
  final StreamController<RunPoint> _c = StreamController<RunPoint>.broadcast();
  int starts = 0;
  @override
  Stream<RunPoint> get fixes => _c.stream;
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> stop() async {}
  void emit(RunPoint p) => _c.add(p);
  void fail(Object e) => _c.addError(e);
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('Allow location while paused mid-run resumes the same run instead of '
      'starting a second one', () async {
    final source = _Source();
    var n = 0;
    var clock = DateTime(2026, 9, 29, 7);
    final recorder = RecordingRunRecorder(
      source: source,
      db: db,
      newId: () => 'run-${++n}',
      now: () => clock,
    );
    await recorder.start();
    for (var i = 0; i < 20; i++) {
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
    clock = clock.add(const Duration(minutes: 20));

    // The permission changes mid-run, the same way iOS/Android report it.
    source.fail(
      const LocationUnavailable(LocationUnavailableReason.permissionDenied),
    );
    await pumpEventQueue();
    expect(recorder.problem, RecorderProblem.permissionDenied);
    expect(recorder.status, RecorderStatus.recording);

    await recorder.pause();
    // The panel's "Allow location" button is RecordingScreen._askAgain:
    await recorder.start();
    expect(recorder.status, RecorderStatus.recording);
    expect(recorder.problem, isNull);
    // No new id was minted and no new row created.
    expect(n, 1);

    source.emit(
      RunPoint(
        latitude: 51.6,
        longitude: -0.10,
        accuracyMeters: 5,
        timestamp: clock,
      ),
    );
    await pumpEventQueue(times: 200);

    await recorder.pause();
    await recorder.stop();

    final all = await db.allRuns();
    final log = await DriftRunRepository(db).fetchRuns();
    final points = await db.pointsForRun('run-1');

    expect(all, hasLength(1), reason: 'no orphaned second run');
    expect(log.map((r) => r.id), <String>['run-1']);
    // 20 fixes before the problem, one after the restart — each stored
    // once, not twice.
    expect(points, hasLength(21));
    expect(source.starts, 2, reason: 'the original start, plus the retry');
  });
}
