import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/history/data/drift_run_repository.dart';
import 'package:mgk_run/src/features/recording/data/location_source.dart';
import 'package:mgk_run/src/features/recording/data/recording_run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// **Where a record is computed, and why it is not computed when Profile
/// opens.**
///
/// A record is the fastest continuous stretch of a standard distance inside a
/// run, which means walking every point of the trace. Doing that on demand
/// would mean loading every point of every run in the log on every visit to a
/// tab, over a log that only grows — the same read ADR-0023 took off the
/// network and this takes off the critical path. So it happens once, at the
/// finish line, beside the splits and the elevation figures that already come
/// out of that same walk.
///
/// The other half of this file is the backfill. Runs recorded before schema 9
/// have traces and no records, and unlike schema 8's step count there is no
/// invention involved in filling them: the evidence is on the phone, and the
/// migration runs exactly the window the recorder would have run.
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

void main() {
  /// Metres per degree of latitude on the sphere `haversineMeters` uses, so a
  /// fixture can be laid out at exact distances (see `best_effort_test.dart`).
  const double metersPerDegree = 6371000.0 * math.pi / 180.0;

  final started = DateTime(2026, 8, 23, 14, 2);

  late AppDatabase db;
  late _FakeLocationSource source;
  late DateTime clock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    source = _FakeLocationSource();
    clock = started;
  });

  tearDown(() async {
    await source.dispose();
    await db.close();
  });

  /// A straight run of [meters] at [secondsPerKm], one fix every 50 m — close
  /// enough together that `kMaxTraceGap` never fires.
  List<RunPoint> straight({
    required double meters,
    required double secondsPerKm,
  }) => <RunPoint>[
    for (var covered = 0.0; covered <= meters + 1e-9; covered += 50)
      RunPoint(
        latitude: 51.0 + covered / metersPerDegree,
        longitude: -0.1,
        accuracyMeters: 5,
        timestamp: started.add(
          Duration(
            milliseconds: (covered / 1000 * secondsPerKm * 1000).round(),
          ),
        ),
      ),
  ];

  Future<void> recordRun(List<RunPoint> trace, {String id = 'run-1'}) async {
    final recorder = RecordingRunRecorder(
      source: source,
      db: db,
      newId: () => id,
      now: () => clock,
    );
    await recorder.start();
    for (final point in trace) {
      clock = point.timestamp;
      source.emit(point);
      await pumpEventQueue();
    }
    await recorder.stop();
  }

  /// Writes a run row and its trace straight to the database, the way a run
  /// recorded before schema 9 sits there: points, no records.
  Future<void> storeUnanalysed(
    String id,
    List<RunPoint> trace, {
    double? distanceM,
  }) async {
    await db.upsertRun(
      RunsCompanion.insert(
        id: id,
        startedAt: started,
        endedAt: Value(started.add(const Duration(minutes: 30))),
        durationS: 1800,
        distanceM: distanceM ?? 10000,
        source: 'gps',
        type: 'outdoor',
      ),
    );
    for (var i = 0; i < trace.length; i++) {
      await db.addRunPoint(
        RunPointsCompanion.insert(
          runId: id,
          seq: i,
          lat: trace[i].latitude,
          lng: trace[i].longitude,
          accuracyM: trace[i].accuracyMeters,
          timestamp: trace[i].timestamp,
        ),
      );
    }
  }

  group('records go down with the run', () {
    test('a 10 km run stores its 5K and its 10K, and nothing longer', () async {
      await recordRun(straight(meters: 10180, secondsPerKm: 345));

      final rows = await db.bestEffortsForRun('run-1');

      expect(rows.map((r) => r.distanceM).toList(), <double>[5000, 10000]);
      // 10.18 km at 5:45/km takes 58:32; the 10 km inside it takes 57:30. The
      // gap is the whole argument for searching rather than reading the summary
      // — a whole-run record would understate this runner by a minute.
      expect(rows.last.durationS, closeTo(3450, 2));
      expect(
        rows.last.durationS,
        lessThan((await db.runById('run-1'))!.durationS),
      );
    });

    test('a run too short to hold one stores nothing', () async {
      await recordRun(straight(meters: 3000, secondsPerKm: 300));

      expect(await db.bestEffortsForRun('run-1'), isEmpty);
    });

    test('the records reach the log the profile folds', () async {
      await recordRun(straight(meters: 5200, secondsPerKm: 300));

      final List<RunSummary> log = await DriftRunRepository(db).fetchRuns();

      expect(log, hasLength(1));
      expect(log.single.bestEfforts, hasLength(1));
      expect(log.single.bestEfforts.single.distanceMeters, 5000);
      expect(
        log.single.bestEfforts.single.duration.inSeconds,
        closeTo(1500, 2),
      );
    });

    test('a single run read in full carries them too', () async {
      await recordRun(straight(meters: 5200, secondsPerKm: 300));

      final RunSummary? detail = await DriftRunRepository(
        db,
      ).runDetail('run-1');

      expect(detail!.bestEfforts, hasLength(1));
    });

    test('writing twice replaces rather than duplicates', () async {
      await recordRun(straight(meters: 5200, secondsPerKm: 300));
      await db.replaceRunBestEfforts('run-1', <RunBestEffortsCompanion>[
        RunBestEffortsCompanion.insert(
          runId: 'run-1',
          distanceM: 5000,
          durationS: 1400,
        ),
      ]);

      final rows = await db.bestEffortsForRun('run-1');

      expect(rows, hasLength(1));
      expect(rows.single.durationS, 1400);
    });

    test('discarding a run takes its records with it', () async {
      await recordRun(straight(meters: 5200, secondsPerKm: 300));
      expect(await db.bestEffortsForRun('run-1'), isNotEmpty);

      await db.deleteRun('run-1');

      // A row left behind here would outlive the run it describes and go on
      // standing as a lifetime best for a run the runner deleted.
      expect(await db.bestEffortsForRun('run-1'), isEmpty);
      expect(await db.allBestEfforts(), isEmpty);
    });
  });

  group('the backfill schema 9 runs', () {
    test('fills a run that has a trace and no records', () async {
      await storeUnanalysed('old-1', straight(meters: 5400, secondsPerKm: 300));

      expect(await db.backfillBestEfforts(), 1);

      final rows = await db.bestEffortsForRun('old-1');
      expect(rows, hasLength(1));
      expect(rows.single.durationS, closeTo(1500, 2));
    });

    test('leaves a run that already has them alone', () async {
      await storeUnanalysed('old-1', straight(meters: 5400, secondsPerKm: 300));
      await db.replaceRunBestEfforts('old-1', <RunBestEffortsCompanion>[
        RunBestEffortsCompanion.insert(
          runId: 'old-1',
          distanceM: 5000,
          durationS: 1234,
        ),
      ]);

      expect(await db.backfillBestEfforts(), 0);
      expect((await db.bestEffortsForRun('old-1')).single.durationS, 1234);
    });

    test('passes over a run with no trace', () async {
      // A hand-entered marathon. Nothing to search, and its own time is not a
      // substitute — that is the rule, not an oversight (ADR-0026).
      await db.upsertRun(
        RunsCompanion.insert(
          id: 'typed',
          startedAt: started,
          endedAt: Value(started.add(const Duration(hours: 3, minutes: 48))),
          durationS: 13680,
          distanceM: 42195,
          source: 'manual',
          type: 'outdoor',
        ),
      );

      expect(await db.backfillBestEfforts(), 0);
      expect(await db.allBestEfforts(), isEmpty);
    });

    test('judges a run by its trace, never by its corrected distance', () async {
      // A GPS run whose summary was edited down to 4 km. The distance is the
      // runner's account and the trace is the evidence (ADR-0016), and a record
      // is read off the evidence — so filtering candidates on `distanceM` would
      // silently drop a run holding five real kilometres of road.
      await storeUnanalysed(
        'corrected',
        straight(meters: 5400, secondsPerKm: 300),
        distanceM: 4000,
      );

      expect(await db.backfillBestEfforts(), 1);
      expect(await db.bestEffortsForRun('corrected'), hasLength(1));
    });

    test('is safe to run again over a log it has already walked', () async {
      await storeUnanalysed('old-1', straight(meters: 5400, secondsPerKm: 300));
      await db.backfillBestEfforts();

      expect(await db.backfillBestEfforts(), 0);
      expect(await db.bestEffortsForRun('old-1'), hasLength(1));
    });

    test('runs for real when the database is opened at version 8', () async {
      // **The one test that exercises the migration rather than the method it
      // calls.** A backfill that works on its own and throws inside `onUpgrade`
      // would leave the app unable to open its own database, which is the worst
      // failure in the file and the one no unit test of the walk can find:
      // drift's `batch` and `transaction` both open a transaction, and a
      // migration is already one.
      //
      // Version 8 is faked by undoing everything the migrations after it did
      // and winding `user_version` back — which is exactly the state a phone
      // updating from that build is in. Every additive step has to be undone,
      // not just schema 9's: `onCreate` builds the *current* schema, so a
      // database left with schema 10's columns and `user_version = 8` is not a
      // version 8 database and the migration correctly refuses it with a
      // duplicate column. Adding a column to `plans` without touching this is
      // how that discovery gets made.
      // Two databases over one file is the whole point here, so drift's
      // (correct, in general) warning about it is noise in this one test.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );

      final dir = Directory.systemTemp.createTempSync('mgk_run_migration');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'runio.sqlite'));

      var upgrading = AppDatabase(NativeDatabase(file));
      await upgrading.upsertRun(
        RunsCompanion.insert(
          id: 'old-1',
          startedAt: started,
          endedAt: Value(started.add(const Duration(minutes: 27))),
          durationS: 1620,
          distanceM: 5400,
          source: 'gps',
          type: 'outdoor',
        ),
      );
      final trace = straight(meters: 5400, secondsPerKm: 300);
      for (var i = 0; i < trace.length; i++) {
        await upgrading.addRunPoint(
          RunPointsCompanion.insert(
            runId: 'old-1',
            seq: i,
            lat: trace[i].latitude,
            lng: trace[i].longitude,
            accuracyM: trace[i].accuracyMeters,
            timestamp: trace[i].timestamp,
          ),
        );
      }
      await upgrading.customStatement('DROP TABLE run_best_efforts');
      await upgrading.customStatement(
        'ALTER TABLE plans DROP COLUMN finished_at',
      );
      await upgrading.customStatement(
        'ALTER TABLE plans DROP COLUMN race_time_s',
      );
      // Schema 11's additions, undone for the same reason 9's and 10's are.
      await upgrading.customStatement(
        'ALTER TABLE runs DROP COLUMN paused_total_s',
      );
      await upgrading.customStatement(
        'ALTER TABLE runs DROP COLUMN not_counting_since',
      );
      await upgrading.customStatement('PRAGMA user_version = 8');
      await upgrading.close();

      upgrading = AppDatabase(NativeDatabase(file));
      addTearDown(upgrading.close);

      // Reading forces the open, which runs the migration.
      final rows = await upgrading.bestEffortsForRun('old-1');

      expect(rows, hasLength(1));
      expect(rows.single.distanceM, 5000);
      expect(rows.single.durationS, closeTo(1500, 2));
    });
  });
}
