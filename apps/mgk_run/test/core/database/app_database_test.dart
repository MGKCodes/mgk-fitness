import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  RunsCompanion aRun({String id = 'run-1', double distanceM = 5000}) =>
      RunsCompanion.insert(
        id: id,
        startedAt: DateTime.utc(2026, 1, 1, 8),
        durationS: 1800,
        distanceM: distanceM,
        source: 'gps',
        type: 'outdoor',
      );

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('persists a run and its points, read back in recorded order', () async {
    await db.upsertRun(aRun());

    for (var i = 0; i < 3; i++) {
      await db.addRunPoint(
        RunPointsCompanion.insert(
          runId: 'run-1',
          seq: i,
          lat: 51.5 + i * 0.001,
          lng: -0.12,
          accuracyM: 5,
          timestamp: DateTime.utc(2026, 1, 1, 8, 0, i),
        ),
      );
    }

    final runs = await db.allRuns();
    expect(runs, hasLength(1));
    expect(runs.single.distanceM, 5000);
    expect(runs.single.source, 'gps');

    final points = await db.pointsForRun('run-1');
    expect(points.map((pt) => pt.seq), [0, 1, 2]);
    expect(points.first.lat, closeTo(51.5, 1e-9));
    expect(points.first.altitudeM, isNull);
  });

  test('upsertRun replaces an existing run', () async {
    await db.upsertRun(aRun());
    await db.upsertRun(aRun(distanceM: 5200));

    final runs = await db.allRuns();
    expect(runs, hasLength(1));
    expect(runs.single.distanceM, 5200);
  });

  test('watchRuns reflects an inserted run', () async {
    // drift's initial emission races with the insert, so assert the stream
    // reaches a state with one run rather than a fixed [0, 1] sequence.
    final expectation = expectLater(
      db.watchRuns().map((rows) => rows.length),
      emitsThrough(1),
    );
    await db.upsertRun(aRun());
    await expectation;
  });
}
