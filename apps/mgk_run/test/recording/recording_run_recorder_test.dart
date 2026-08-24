import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/recording/data/location_source.dart';
import 'package:mgk_run/src/features/recording/data/recording_run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';

class FakeLocationSource implements LocationSource {
  FakeLocationSource({this.failOnStart});

  /// Refuses to start, the way a denied permission or a switched-off location
  /// service does.
  final LocationUnavailable? failOnStart;

  final StreamController<RunPoint> _controller =
      StreamController<RunPoint>.broadcast();
  bool started = false;

  @override
  Stream<RunPoint> get fixes => _controller.stream;

  @override
  Future<void> start() async {
    final failure = failOnStart;
    if (failure != null) throw failure;
    started = true;
  }

  @override
  Future<void> stop() async => started = false;

  void emit(RunPoint point) => _controller.add(point);

  /// A failure arriving mid-run, after a clean start.
  void fail(LocationUnavailable error) => _controller.addError(error);

  Future<void> dispose() => _controller.close();
}

/// Emits its one fix from inside [start], which is the window a broadcast
/// stream drops anything landing in unless the listener is already attached.
class _EagerLocationSource implements LocationSource {
  _EagerLocationSource(this.fix);

  final RunPoint fix;
  final StreamController<RunPoint> _controller =
      StreamController<RunPoint>.broadcast();

  @override
  Stream<RunPoint> get fixes => _controller.stream;

  @override
  Future<void> start() async => _controller.add(fix);

  @override
  Future<void> stop() async {}

  Future<void> dispose() => _controller.close();
}

RunPoint _fix(double lat, double lng, {double accuracy = 5, DateTime? at}) =>
    RunPoint(
      latitude: lat,
      longitude: lng,
      accuracyMeters: accuracy,
      timestamp: at ?? DateTime(2026, 1, 1),
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

  group('the two accuracy gates', () {
    // The bug this exists to stop coming back: one 20 m gate discarded fixes
    // before they were persisted, so in ordinary running conditions (tree
    // cover, tall buildings, the first half-minute of any run) the app stored
    // nothing, drew nothing, and showed 0.00 km with no way to tell that from
    // a broken GPS.
    test('records a mediocre fix that it refuses to measure with', () async {
      await recorder.start();
      source.emit(_fix(0, 0, accuracy: 5));
      source.emit(_fix(0, 0.001, accuracy: 35)); // usable position, poor fix
      await pumpEventQueue();

      // Persisted and drawable...
      expect((await db.pointsForRun('run-1')).length, 2);
      expect(recorder.lastFix?.accuracyMeters, 35);
      // ...but it did not move the number.
      expect(recorder.distanceMeters, 0);
    });

    test('a whole run of mediocre fixes still draws a route', () async {
      await recorder.start();
      for (var i = 0; i < 5; i++) {
        source.emit(_fix(0, i * 0.001, accuracy: 40));
      }
      await pumpEventQueue();

      expect((await db.pointsForRun('run-1')).length, 5);
    });

    test('genuinely useless fixes are still discarded', () async {
      await recorder.start();
      source.emit(_fix(0, 0, accuracy: 65)); // opening cell/wifi fix
      await pumpEventQueue();

      expect(await db.pointsForRun('run-1'), isEmpty);
      expect(recorder.lastFix, isNull);
    });
  });

  group('elapsed', () {
    // Elapsed used to be accumulated by a 1 Hz ticker in the screen, which iOS
    // throttles and then suspends behind a locked screen. A backgrounded run
    // came back minutes short, and pace — derived from it — was wrong to match.
    test('follows the wall clock, not the number of ticks', () async {
      await recorder.start();
      clock = clock.add(const Duration(minutes: 12));

      expect(recorder.elapsed, const Duration(minutes: 12));
    });

    test('stops when the runner presses Pause, and only then', () async {
      // A pause is a deliberate act: pressing it means "this next bit is not
      // my run", and the clock owes them that. The counterpart — that merely
      // stopping running does NOT stop it — is pinned in the standing-still
      // group below.
      await recorder.start();
      clock = clock.add(const Duration(minutes: 5));
      await recorder.pause();

      clock = clock.add(const Duration(minutes: 30)); // a long coffee
      expect(recorder.elapsed, const Duration(minutes: 5));

      await recorder.resume();
      clock = clock.add(const Duration(minutes: 2));
      expect(recorder.elapsed, const Duration(minutes: 7));
    });

    test('a stopped run stores exactly what the screen showed', () async {
      // Storing anything else means the summary disagrees with the run, which
      // it did in both directions within a day: first wall time against a
      // moving-time display, then the reverse. durationS is also the divisor
      // for avgPaceSPerKm, so a mismatch shows up as a pace nobody ran.
      await recorder.start();
      source.emit(_fix(0, 0));
      await pumpEventQueue();

      clock = clock.add(const Duration(minutes: 10));
      await recorder.pause();
      clock = clock.add(const Duration(minutes: 20));
      await recorder.resume();
      clock = clock.add(const Duration(minutes: 5));
      await recorder.stop();

      expect((await db.runById('run-1'))!.durationS, 15 * 60);
    });

    test('the clock stops at the line, not when the summary closes', () async {
      await recorder.start();
      clock = clock.add(const Duration(minutes: 20));
      await recorder.stop();

      clock = clock.add(const Duration(hours: 2)); // summary left open
      expect(recorder.elapsed, const Duration(minutes: 20));
    });
  });

  group('pause', () {
    test('does not add the distance covered while paused', () async {
      await recorder.start();
      source.emit(_fix(0, 0));
      await pumpEventQueue();
      final before = recorder.distanceMeters;

      await recorder.pause();
      await recorder.resume();
      // Resuming a long way from where the runner paused: a walk to a cafe,
      // or a drive home. The anchor is dropped on pause, so the first fix
      // after resuming starts a new segment instead of measuring back.
      source.emit(_fix(0, 0.01));
      await pumpEventQueue();

      expect(recorder.distanceMeters, before);
    });

    test('the recomputed total at stop ignores the gap too', () async {
      // The live figure and the figure recomputed from the persisted trace are
      // two different code paths, and they have to agree — otherwise the run
      // grows the moment it is saved.
      final start = DateTime(2026, 1, 1, 8);
      await recorder.start();
      source.emit(_fix(0, 0, at: start));
      source.emit(_fix(0, 0.001, at: start.add(const Duration(seconds: 30))));
      await pumpEventQueue();

      await recorder.pause();
      await recorder.resume();
      // Ten minutes later and a kilometre away — a gap, not a stride.
      source.emit(_fix(0, 0.01, at: start.add(const Duration(minutes: 10))));
      source.emit(
        _fix(0, 0.011, at: start.add(const Duration(minutes: 10, seconds: 30))),
      );
      await pumpEventQueue();

      clock = clock.add(const Duration(minutes: 20));
      await recorder.stop();

      // Two segments of ~111 m each, and nothing for the ~1 km hole between.
      expect((await db.runById('run-1'))!.distanceM, closeTo(222.39, 1));
    });
  });

  group('a runner standing still', () {
    /// Fixes at a fixed spot, one a second — a runner waiting at a light, with
    /// the metres of GPS drift a stationary phone really produces.
    void standStill({required int seconds}) {
      for (var i = 0; i <= seconds; i++) {
        source.emit(
          _fix(
            (i.isEven ? 1 : -1) * 0.00003, // ~3 m either side
            0,
            at: DateTime(2026, 1, 1, 8).add(Duration(seconds: i)),
          ),
        );
      }
    }

    // These exist because an autopause heuristic was wired in, shipped, and on
    // the first device run latched within seconds and never released: the clock
    // froze and nothing was written. It has been removed, and these pin the
    // properties its absence guarantees.

    test('is still recorded — a guess never stops the writing', () async {
      await recorder.start();
      standStill(seconds: 40);
      await pumpEventQueue();

      // Rule 1: a fix that arrives is a fix on disk. Nothing between the
      // source and the write is allowed a vote.
      expect((await db.pointsForRun('run-1')).length, 41);
    });

    test('does not stop the clock — only the runner does that', () async {
      await recorder.start();
      standStill(seconds: 40);
      await pumpEventQueue();

      clock = clock.add(const Duration(minutes: 5));
      expect(recorder.elapsed, const Duration(minutes: 5));
      expect(recorder.status, RecorderStatus.recording);
    });

    test(
      'DOES still bank the drift as distance — a known, open defect',
      () async {
        // Characterisation, not approval. Autopause was reached for to solve
        // this, and the justification for unwiring it originally claimed the
        // jitter rule in processedDistanceMeters already handled it. It does
        // not: that rule only discards sub-metre hops, and real GPS drift is
        // metres. Forty seconds standing still banks a few hundred of them.
        //
        // Pinned so the number is visible and cannot quietly get worse. When
        // the smoother learns to reject drift by implied speed, this test
        // should fail — and the fix is to tighten the bound, not delete it.
        await recorder.start();
        standStill(seconds: 40);
        await pumpEventQueue();

        clock = clock.add(const Duration(minutes: 1));
        await recorder.stop();

        final banked = (await db.runById('run-1'))!.distanceM;
        expect(banked, greaterThan(100), reason: 'the defect is still present');
        expect(banked, lessThan(400), reason: 'and has not got worse');
      },
    );
  });

  group('when location is unavailable', () {
    test('surfaces the reason instead of throwing into nowhere', () async {
      // start() is called from initState, where nothing catches. Throwing made
      // it an unhandled async error and left the screen pulsing "Recording"
      // over stats that would never move.
      final denied = FakeLocationSource(
        failOnStart: const LocationUnavailable(
          LocationUnavailableReason.permissionDeniedForever,
        ),
      );
      final failing = RecordingRunRecorder(
        source: denied,
        db: db,
        newId: () => 'run-2',
        now: () => clock,
      );

      await expectLater(failing.start(), completes);

      expect(failing.problem, RecorderProblem.permissionDeniedForever);
      expect(failing.status, RecorderStatus.idle);
      await denied.dispose();
    });

    test('leaves no phantom run to recover', () async {
      final off = FakeLocationSource(
        failOnStart: const LocationUnavailable(
          LocationUnavailableReason.servicesDisabled,
        ),
      );
      final failing = RecordingRunRecorder(
        source: off,
        db: db,
        newId: () => 'run-3',
        now: () => clock,
      );

      await failing.start();

      // An in-progress row with a null endedAt is the recovery marker, so a run
      // that never started must not leave one behind.
      expect(await db.activeRun(), isNull);
      expect(failing.problem, RecorderProblem.locationServicesOff);
      await off.dispose();
    });

    test('reports a failure that arrives mid-run', () async {
      final seen = <RecorderProblem?>[];
      recorder.problems.listen(seen.add);

      await recorder.start();
      source.emit(_fix(0, 0));
      await pumpEventQueue();

      source.fail(
        const LocationUnavailable(LocationUnavailableReason.permissionDenied),
      );
      await pumpEventQueue();

      expect(recorder.problem, RecorderProblem.permissionDenied);

      // And clears itself when fixes start arriving again.
      source.emit(_fix(0, 0.001));
      await pumpEventQueue();
      expect(recorder.problem, isNull);
      expect(seen, contains(RecorderProblem.permissionDenied));
    });
  });

  test('a fix arriving the instant the source starts is not lost', () async {
    // `fixes` is a broadcast stream, so anything emitted before the recorder
    // subscribes is discarded. Subscribing after `start()` threw away the
    // opening fixes of every run on a warm GPS.
    final eager = _EagerLocationSource(_fix(0, 0));
    final quick = RecordingRunRecorder(
      source: eager,
      db: db,
      newId: () => 'run-4',
      now: () => clock,
    );

    await quick.start();
    await pumpEventQueue();

    expect((await db.pointsForRun('run-4')).length, 1);
    await eager.dispose();
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

  group('the splits go down with the run', () {
    // **They used to be computed and thrown away.** The recorder cut them on
    // every fix for the in-run readout and stored none, so `run_splits` was
    // filled only by a restore — a run finished on this phone had ten splits
    // until the screen closed and none afterwards, and the summary it was
    // meant to be sent to could only ever show an empty list (ADR-0023).

    /// A straight run east along the equator, where 0.001 degrees of longitude
    /// is ~111.19 m. Twenty-one hops is ~2,335 m: two whole kilometres and a
    /// short remainder.
    Future<void> recordTwoAndABitKilometres() async {
      final start = clock;
      await recorder.start();
      for (var i = 0; i <= 21; i++) {
        source.emit(
          _fix(0, i * 0.001, at: start.add(Duration(seconds: i * 5))),
        );
      }
      await pumpEventQueue();
      clock = clock.add(const Duration(minutes: 12));
    }

    test('stop writes them, so a finished run has splits to show', () async {
      await recordTwoAndABitKilometres();
      await recorder.stop();

      final splits = await db.splitsForRun('run-1');
      expect(splits, hasLength(3));
      expect(splits[0].seq, 1);
      expect(splits[0].distanceM, closeTo(1000, 0.5));
      expect(splits[1].seq, 2);
      expect(splits[1].distanceM, closeTo(1000, 0.5));
      // The trailing partial is kept and is honestly short — the same rule the
      // splits list already renders.
      expect(splits[2].distanceM, lessThan(1000));
      expect(splits.every((s) => s.durationS > 0), isTrue);
    });

    test('and they are written before the mirror reads them back', () async {
      // `pushTrace` selects the splits out of the database, so writing them
      // after the push would mirror a run with none.
      await recordTwoAndABitKilometres();
      await recorder.stop();

      expect(await db.splitsForRun('run-1'), hasLength(3));
    });

    test('finishing twice replaces them rather than doubling them', () async {
      await recordTwoAndABitKilometres();
      await recorder.stop();
      await recorder.stop();

      expect(await db.splitsForRun('run-1'), hasLength(3));
    });

    test('a run with no trace stores no splits, which is not a gap', () async {
      await recorder.start();
      clock = clock.add(const Duration(minutes: 3));
      await recorder.stop();

      expect(await db.splitsForRun('run-1'), isEmpty);
    });

    test('a discarded run takes its splits with it', () async {
      await recordTwoAndABitKilometres();
      await recorder.stop();
      expect(await db.splitsForRun('run-1'), isNotEmpty);

      await recorder.discard();
      expect(await db.splitsForRun('run-1'), isEmpty);
    });
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
