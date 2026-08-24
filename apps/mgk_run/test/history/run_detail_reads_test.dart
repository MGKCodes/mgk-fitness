import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/history/data/drift_run_repository.dart';
import 'package:mgk_run/src/features/history/data/run_editor.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';
import 'package:mgk_run/src/features/history/domain/run_writer.dart';
import 'package:mgk_run/src/features/recording/data/location_source.dart';
import 'package:mgk_run/src/features/recording/data/recording_run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';

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

RunPoint _fix(double lng, DateTime at) =>
    RunPoint(latitude: 0, longitude: lng, accuracyMeters: 5, timestamp: at);

/// **A run opened from the log had never drawn a route.**
///
/// The old Supabase read returned summaries, and the `fetchRunDetail` sitting
/// beside it was called by nothing at all — so `RunSummaryScreen` had a map
/// that only ever appeared for a run handed to it in memory, which was no run
/// at all until finishing was wired to it. ADR-0023 left this as the one
/// consequence still open. These are the local reads that close it, over a real
/// Drift database and the real recorder: nothing between the run being recorded
/// and the screen being able to draw it.
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

  /// Records a run of about 2.3 km — far enough to close two kilometres, so
  /// there are splits as well as a trace.
  Future<String> recordARun({String id = 'run-1'}) async {
    final recorder = RecordingRunRecorder(
      source: source,
      db: db,
      newId: () => id,
      now: () => clock,
    );
    final start = clock;
    await recorder.start();
    for (var i = 0; i <= 21; i++) {
      source.emit(_fix(i * 0.001, start.add(Duration(seconds: i * 5))));
    }
    await pumpEventQueue();
    clock = clock.add(const Duration(minutes: 12));
    await recorder.stop();
    return id;
  }

  group('runDetail', () {
    test('brings back the trace and the splits, not just the row', () async {
      await recordARun();

      final detail = await DriftRunRepository(db).runDetail('run-1');

      expect(detail, isNotNull);
      expect(detail!.id, 'run-1');
      expect(detail.points, hasLength(22));
      expect(detail.splits, hasLength(3));
      expect(
        detail.hasRoute,
        isTrue,
        reason: 'this is the whole point — the map has something to draw',
      );
    });

    test('the log itself still reads summaries only', () async {
      // A list of runs draws none of the trace, and a run is thousands of rows.
      // Loading them for every row of the log would be paying for a map nobody
      // is looking at.
      await recordARun();

      final log = await DriftRunRepository(db).fetchRuns();

      expect(log.single.points, isEmpty);
      expect(log.single.hasRoute, isFalse);
    });

    test('the mapping keeps latitude and longitude the right way round', () {
      // The failure this guards is a plausible route drawn in the sea, which
      // looks like a map bug rather than a mapping one.
      final point = runPointFromLocal(
        RunPointRow(
          runId: 'run-1',
          seq: 0,
          lat: 51.5,
          lng: -0.12,
          accuracyM: 5,
          timestamp: DateTime(2026, 8, 23, 9),
        ),
      );

      expect(point.latitude, 51.5);
      expect(point.longitude, -0.12);
    });

    test('null for a run that is not there', () async {
      expect(await DriftRunRepository(db).runDetail('nobody'), isNull);
    });

    test('a hand-entered run comes back with no trace and no error', () async {
      // A treadmill run has no route and no splits. That is a normal state, not
      // missing data — the screen simply draws no map.
      final editor = RunEditor(db: db, now: () => clock, newId: () => 'm-1');
      await editor.add(
        RunDraft(
          startedAt: clock.subtract(const Duration(days: 1)),
          duration: const Duration(minutes: 26),
          distanceMeters: 5000,
          type: kTypeTreadmill,
        ),
      );

      final detail = await DriftRunRepository(db).runDetail('m-1');

      expect(detail, isNotNull);
      expect(detail!.points, isEmpty);
      expect(detail.splits, isEmpty);
      expect(detail.hasRoute, isFalse);
    });
  });

  group('runFinishedSince', () {
    test('finds the run that was just recorded', () async {
      final openedAt = clock;
      await recordARun();

      final run = await DriftRunRepository(db).runFinishedSince(openedAt);

      expect(run?.id, 'run-1');
      expect(run!.points, isNotEmpty, reason: 'in full, for the summary');
    });

    test('finds nothing when no run was recorded', () async {
      // The case that matters. A runner who opened the recorder and backed out
      // — or whose permission was refused — must not be shown the *previous*
      // run's summary as though they had just done it.
      await recordARun();
      final openedAt = clock.add(const Duration(minutes: 1));

      expect(await DriftRunRepository(db).runFinishedSince(openedAt), isNull);
    });

    test('is asked by when a run ended, not by when it started', () async {
      // The reason this is not "the newest row in the log". A run hand-entered
      // this morning about yesterday evening can sit anywhere in a `startedAt`
      // ordering; only `endedAt` says which run finished last, and the editor
      // writes it as start + duration, which is in the past.
      final openedAt = clock;
      await recordARun();
      final editor = RunEditor(db: db, now: () => clock, newId: () => 'm-1');
      await editor.add(
        RunDraft(
          // Started *after* the recorded run began, and finished before it did.
          startedAt: openedAt.add(const Duration(minutes: 1)),
          duration: const Duration(minutes: 2),
          distanceMeters: 900,
          type: kTypeTreadmill,
        ),
      );

      final run = await DriftRunRepository(db).runFinishedSince(openedAt);

      expect(run?.id, 'run-1');
    });

    test('ignores a run still in progress', () async {
      // A null `endedAt` cannot be greater than anything, so an interrupted run
      // is excluded by the query rather than by a second filter.
      final openedAt = clock;
      final recorder = RecordingRunRecorder(
        source: source,
        db: db,
        newId: () => 'live',
        now: () => clock,
      );
      await recorder.start();
      source.emit(_fix(0, clock));
      await pumpEventQueue();

      expect(await DriftRunRepository(db).runFinishedSince(openedAt), isNull);
    });
  });

  test('the editor answers both, so the shell can reach them', () async {
    // The shell is handed `historySource` as a bare tear-off of one query, so
    // the editor is the one injected object that still knows which database to
    // ask. It delegates rather than duplicating the queries — this asserts the
    // seam is actually there, since a screen finding it by cast gets null
    // silently if it is not.
    await recordARun();
    final editor = RunEditor(db: db, now: () => clock);

    expect(editor, isA<RunDetailSource>());
    final reads = editor as RunDetailSource;
    expect((await reads.runDetail('run-1'))?.points, hasLength(22));
    expect(
      (await reads.runFinishedSince(DateTime(2026, 8, 23, 9)))?.id,
      'run-1',
    );
  });
}
