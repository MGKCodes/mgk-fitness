import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/recording/data/location_source.dart';
import 'package:mgk_run/src/features/recording/data/recording_run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';

class FakeLocationSource implements LocationSource {
  final StreamController<RunPoint> _controller =
      StreamController<RunPoint>.broadcast();
  bool started = false;

  @override
  Stream<RunPoint> get fixes => _controller.stream;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async => started = false;

  void emit(RunPoint point) => _controller.add(point);

  Future<void> dispose() => _controller.close();
}

RunPoint _fix(double lat, double lng, {double accuracy = 5}) => RunPoint(
  latitude: lat,
  longitude: lng,
  accuracyMeters: accuracy,
  timestamp: DateTime(2026, 1, 1),
);

void main() {
  late AppDatabase db;
  late FakeLocationSource source;
  late RecordingRunRecorder recorder;
  late DateTime clock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    source = FakeLocationSource();
    clock = DateTime(2026, 1, 1, 8);
    recorder = RecordingRunRecorder(
      source: source,
      db: db,
      newId: () => 'run-1',
      now: () => clock,
    );
  });

  tearDown(() async {
    await source.dispose();
    await db.close();
  });

  test('start creates an in-progress run row', () async {
    await recorder.start();

    final active = await db.activeRun();
    expect(active, isNotNull);
    expect(active!.id, 'run-1');
    expect(active.endedAt, isNull);
    expect(recorder.status, RecorderStatus.recording);
    expect(source.started, isTrue);
  });

  test(
    'persists each fix, and only emits points that are already stored',
    () async {
      final emitted = <RunPoint>[];
      recorder.points.listen(emitted.add);

      await recorder.start();
      source.emit(_fix(0, 0));
      source.emit(_fix(0, 0.001));
      await pumpEventQueue();

      final stored = await db.pointsForRun('run-1');
      expect(stored.length, 2);
      expect(emitted.length, 2);
    },
  );

  test('drops poor-accuracy fixes', () async {
    await recorder.start();
    source.emit(_fix(0, 0, accuracy: 5));
    source.emit(_fix(0, 0.001, accuracy: 100)); // bad fix
    source.emit(_fix(0, 0.002, accuracy: 5));
    await pumpEventQueue();

    expect((await db.pointsForRun('run-1')).length, 2);
  });

  test('accumulates distance across kept fixes', () async {
    await recorder.start();
    source.emit(_fix(0, 0));
    source.emit(_fix(0, 0.001));
    await pumpEventQueue();

    expect(recorder.distanceMeters, closeTo(111.19, 1));
  });

  test('ignores fixes while paused', () async {
    await recorder.start();
    source.emit(_fix(0, 0));
    await pumpEventQueue();

    await recorder.pause();
    source.emit(_fix(0, 0.001));
    await pumpEventQueue();

    expect((await db.pointsForRun('run-1')).length, 1);
  });

  test('stop finalizes the run and clears the active marker', () async {
    await recorder.start();
    source.emit(_fix(0, 0));
    source.emit(_fix(0, 0.001));
    await pumpEventQueue();

    clock = clock.add(const Duration(minutes: 10));
    await recorder.stop();

    final run = await db.runById('run-1');
    expect(run!.endedAt, isNotNull);
    expect(run.durationS, 600);
    expect(run.distanceM, closeTo(111.19, 1));
    expect(run.avgPaceSPerKm, isNotNull);
    expect(await db.activeRun(), isNull);
    expect(recorder.status, RecorderStatus.stopped);
  });

  test('an interrupted run (no stop) stays recoverable from storage', () async {
    await recorder.start();
    source.emit(_fix(0, 0));
    source.emit(_fix(0, 0.001));
    await pumpEventQueue();

    // Simulate a crash: never call stop(). The run row + points are on disk,
    // and endedAt is still null, so it surfaces as the active run.
    final active = await db.activeRun();
    expect(active, isNotNull);
    expect(active!.id, 'run-1');
    expect((await db.pointsForRun('run-1')).length, 2);
  });
}
