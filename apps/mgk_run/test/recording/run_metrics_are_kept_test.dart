import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/health/domain/run_health_metrics.dart';
import 'package:mgk_run/src/features/history/data/drift_run_repository.dart';
import 'package:mgk_run/src/features/recording/data/location_source.dart';
import 'package:mgk_run/src/features/recording/data/recording_run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// **Strava's summary for the 23 Aug 10 km carried 167 m of gain, a 111 m high
/// point and 8,468 steps. Ours carried none of them.**
///
/// Two different faults behind one symptom, and these are the tests that keep
/// each of them fixed:
///
///  * *Computed and thrown away.* Climb was cut on every fix for the in-run
///    readout and stored nowhere — the splits' bug exactly — so a runner
///    watched a figure tick up for an hour and the summary had no column to
///    read it back from.
///  * *Never asked for.* A GPS trace cannot count steps. Nothing asked Health
///    what the phone counted while the run was happening.
///
/// Everything about the Health half is faked here, and has to be: HealthKit
/// cannot be exercised from a Windows harness (the same constraint ADR-0019
/// records for the permission work). What is proven below is the write path,
/// the window that is asked about, and the absence rules. What the real
/// HealthKit read returns on a phone is not proven by anything in this repo.
class _FakeLocationSource implements LocationSource {
  final StreamController<RunPoint> _controller =
      StreamController<RunPoint>.broadcast();

  @override
  Stream<RunPoint> get fixes => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  void emit(RunPoint point) => _controller.add(point);

  Future<void> dispose() => _controller.close();
}

/// Health, with an answer decided by the test rather than by a phone.
class _FakeHealth implements RunHealthSource {
  _FakeHealth(this.answer);

  final RunHealthMetrics answer;

  DateTime? askedFrom;
  DateTime? askedTo;
  int asks = 0;

  @override
  Future<RunHealthMetrics> forInterval({
    required DateTime start,
    required DateTime end,
  }) async {
    asks++;
    askedFrom = start;
    askedTo = end;
    return answer;
  }
}

void main() {
  late AppDatabase db;
  late _FakeLocationSource source;
  late DateTime clock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    source = _FakeLocationSource();
    clock = DateTime(2026, 8, 23, 9);
  });

  tearDown(() async {
    await source.dispose();
    await db.close();
  });

  RecordingRunRecorder recorderWith({RunHealthSource? health}) =>
      RecordingRunRecorder(
        source: source,
        db: db,
        health: health,
        newId: () => 'run-1',
        now: () => clock,
      );

  RunPoint fix(double lng, {double? altitude}) => RunPoint(
    latitude: 51.5,
    longitude: lng,
    accuracyMeters: 5,
    altitudeMeters: altitude,
    timestamp: clock,
  );

  /// A short run over a trace the test chooses, finished properly.
  Future<void> runOver(
    RecordingRunRecorder recorder,
    List<RunPoint> trace,
  ) async {
    await recorder.start();
    for (final point in trace) {
      source.emit(point);
      clock = clock.add(const Duration(seconds: 5));
      await pumpEventQueue();
    }
    await recorder.stop();
  }

  group('elevation is kept when the run finishes', () {
    test('gain and the high point are both stored, and they differ', () async {
      // Hill repeats in miniature: three times up a 30 m bank. 90 m of gain
      // over a 40 m maximum — the shape that makes reporting one figure for
      // both obviously wrong.
      await runOver(recorderWith(), <RunPoint>[
        fix(-0.100, altitude: 10),
        fix(-0.101, altitude: 40),
        fix(-0.102, altitude: 10),
        fix(-0.103, altitude: 40),
        fix(-0.104, altitude: 10),
        fix(-0.105, altitude: 40),
      ]);

      final row = await db.runById('run-1');
      expect(row!.elevationGainM, closeTo(90, 0.001));
      expect(row.elevationMaxM, 40);
    });

    test('a trace with no altitude stores null, never 0', () async {
      // This is every run the app records today: `GeolocatorLocationSource`
      // supplies no altitude and GPS altitude is deliberately never
      // substituted (ADR-0024). A stored 0 would draw a tile claiming a flat
      // run rather than saying nothing.
      await runOver(recorderWith(), <RunPoint>[
        fix(-0.100),
        fix(-0.101),
        fix(-0.102),
      ]);

      final row = await db.runById('run-1');
      expect(row!.elevationGainM, isNull);
      expect(row.elevationMaxM, isNull);
    });

    test('a flat run has a high point and no gain', () async {
      // The two absences are not the same absence, and the summary is entitled
      // to show one of these without the other.
      await runOver(recorderWith(), <RunPoint>[
        fix(-0.100, altitude: 18),
        fix(-0.101, altitude: 18.2),
        fix(-0.102, altitude: 18),
      ]);

      final row = await db.runById('run-1');
      expect(row!.elevationGainM, isNull);
      expect(row.elevationMaxM, 18.2);
    });
  });

  group('steps come from Health when the run finishes', () {
    test('a step count is stored and reaches the summary', () async {
      final health = _FakeHealth(const RunHealthMetrics(steps: 8468));
      await runOver(recorderWith(health: health), <RunPoint>[
        fix(-0.100),
        fix(-0.101),
      ]);

      expect((await db.runById('run-1'))!.steps, 8468);
      // Read back the way the completion screen reads it, so a column that is
      // written and then dropped by the mapping still fails here.
      final RunSummary? summary = await DriftRunRepository(
        db,
      ).runDetail('run-1');
      expect(summary!.steps, 8468);
    });

    test('Health is asked about the run, over the run\'s own window', () async {
      final health = _FakeHealth(const RunHealthMetrics(steps: 4200));
      final started = clock;
      await runOver(recorderWith(health: health), <RunPoint>[
        fix(-0.100),
        fix(-0.101),
      ]);

      expect(health.asks, 1);
      expect(health.askedFrom, started);
      // Wall clock, not moving time: HealthKit indexes by the calendar, so the
      // window has to be the one the run actually occupied.
      expect(health.askedTo, (await db.runById('run-1'))!.endedAt);
    });

    test('nothing from Health writes nothing at all', () async {
      // A declined read, a phone left at home and a store that timed out are
      // one value here, because iOS cannot tell them apart (CLAUDE.md rule 6).
      // None of them may become a zero in the column.
      final health = _FakeHealth(RunHealthMetrics.none);
      await runOver(recorderWith(health: health), <RunPoint>[
        fix(-0.100),
        fix(-0.101),
      ]);

      expect(health.asks, 1);
      expect((await db.runById('run-1'))!.steps, isNull);
    });

    test('a recorder built the production way still finishes', () async {
      // No health source passed, which is how `main.dart` builds it: the
      // default reads Health on a phone and answers nothing on a desktop, so
      // this is also the run every other test in this suite records.
      await runOver(recorderWith(), <RunPoint>[fix(-0.100), fix(-0.101)]);

      final row = await db.runById('run-1');
      expect(row!.endedAt, isNotNull);
      expect(row.steps, isNull);
    });
  });

  group('the absence rules themselves', () {
    test('none carries nothing and knows it', () {
      expect(RunHealthMetrics.none.steps, isNull);
      expect(RunHealthMetrics.none.isEmpty, isTrue);
      expect(const RunHealthMetrics(steps: 1).isEmpty, isFalse);
    });
  });
}
