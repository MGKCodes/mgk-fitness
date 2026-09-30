/// **Runs, at either end: before the clock starts, and after the app died.**
///
/// Two moments the recording board (`board.dart`) cannot reach, because both
/// belong to the shell rather than to the in-run screen. The start screen and
/// its count-in stand between Home and the clock since the count-in landed;
/// the recovered run is build 26's answer to a run the phone killed before
/// Finish, and it only exists in the log a relaunch reads.
///
/// **The recovered run is recovered for real.** The plate records a run with
/// the app's own recorder into an on-device database, stops it the way a kill
/// does — by never calling `stop()` — and runs the same recovery `main.dart`
/// runs at launch. Nothing about the run on the plate is typed in.
///
/// Regenerate with:
///
///     flutter test test/plates/journeys.dart
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/history/data/drift_run_repository.dart';
import 'package:mgk_run/src/features/history/presentation/run_tile.dart';
import 'package:mgk_run/src/features/profile/presentation/profile_screen.dart';
import 'package:mgk_run/src/features/recording/data/location_source.dart';
import 'package:mgk_run/src/features/recording/data/recording_run_recorder.dart';
import 'package:mgk_run/src/features/recording/data/run_recovery.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';

import 'fixture.dart';
import 'plate.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  // --- Before the clock ------------------------------------------------------

  Widget withARecorder(DriftPlanStore store) => plateApp(
    db,
    store,
    plateLog(),
    recorderFactory: () =>
        FakeRunRecorder(interval: const Duration(milliseconds: 200)),
  );

  testWidgets('the start screen, before anything is recorded', (tester) async {
    final store = DriftPlanStore(db);
    await seedPlan(store);
    await plate(
      tester,
      'run-start',
      withARecorder(store),
      pixelRatio: 2,
      drive: (tester) async {
        await rest(tester);
        await tester.tap(find.text('Start'));
        await settle(tester);
      },
    );
  });

  testWidgets('and the count-in', (tester) async {
    final store = DriftPlanStore(db);
    await seedPlan(store);
    await plate(
      tester,
      'run-count',
      withARecorder(store),
      pixelRatio: 2,
      drive: (tester) async {
        await rest(tester);
        await tester.tap(find.text('Start'));
        await settle(tester);
        await tester.tap(find.text('Start'));
        await tester.pump(const Duration(milliseconds: 200));
      },
    );
    // Let the count finish and the run open, so no timer outlives the test.
    await tester.tap(find.text('Stop'));
    await tester.pump();
  });

  // --- A run the phone killed ------------------------------------------------

  /// Records about 3 km yesterday morning and then dies, the way a swipe from
  /// the app switcher kills it: no `stop()`. Then recovers it as a launch
  /// would.
  Future<void> killedMidRun(WidgetTester tester) async {
    await tester.runAsync(() async {
      final source = _Source();
      final y = DateTime.now().subtract(const Duration(days: 1));
      final t0 = DateTime(y.year, y.month, y.day, 7, 12);
      final recorder = RecordingRunRecorder(
        source: source,
        db: db,
        newId: () => 'killed-run',
        now: () => t0,
      );
      await recorder.start();
      const samples = 300;
      for (var i = 0; i < samples; i++) {
        final t = i / samples * 2 * math.pi;
        final r = 1 + 0.3 * math.sin(3 * t);
        source.emit(
          RunPoint(
            latitude: 51.2300 + 0.0045 * math.sin(t) * r,
            longitude: -0.2050 + 0.0068 * math.cos(t) * r,
            accuracyMeters: 5,
            timestamp: t0.add(Duration(seconds: i * 3)),
          ),
        );
      }
      await pumpEventQueue(times: 4000);
      // Process death: nothing gets to call stop().
      await recoverInterruptedRun(db);
    });
  }

  Widget relaunched(DriftPlanStore store) => plateApp(
    db,
    store,
    const [],
    initialTab: 2,
    historySource: () => DriftRunRepository(db).fetchRuns(),
  );

  Future<void> openTheRun(WidgetTester tester) async {
    await rest(tester);
    final scrollable = find
        .descendant(
          of: find.byType(ProfileScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byType(RunTile),
      280,
      scrollable: scrollable,
    );
    await tester.drag(scrollable, const Offset(0, -250));
    await settle(tester);
    await tester.tap(find.byType(RunTile).first);
    await settle(tester);
    await settle(tester);
  }

  testWidgets('a recovered run, opened from the log', (tester) async {
    await killedMidRun(tester);
    final store = DriftPlanStore(db);
    await plate(
      tester,
      'run-recovered',
      relaunched(store),
      pixelRatio: 2,
      drive: openTheRun,
    );
  });

  testWidgets('and the note it carries, in Edit', (tester) async {
    await killedMidRun(tester);
    final store = DriftPlanStore(db);
    await plate(
      tester,
      'run-recovered-note',
      relaunched(store),
      pixelRatio: 2,
      drive: (tester) async {
        await openTheRun(tester);
        await tester.tap(find.byTooltip('Edit run'));
        await settle(tester);
        // Scrolled to the notes, where recovery writes its sentence.
        await tester.drag(find.text('Kind'), const Offset(0, -400));
        await settle(tester);
      },
    );
  });
}

/// A location source a test can feed fixes to.
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
