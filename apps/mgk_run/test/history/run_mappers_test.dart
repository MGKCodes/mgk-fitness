import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/history/data/run_mappers.dart';

void main() {
  test('runSummaryFromRow maps a full outdoor run row', () {
    final row = <String, dynamic>{
      'id': 'seed-run-02',
      'started_at': '2026-07-07T17:08:54.251331+00:00',
      'duration_s': 5400,
      'distance_m': 15000.0,
      'avg_pace_s_per_km': 360.0,
      'elevation_gain_m': 145.0,
      'avg_hr': 150,
      'max_hr': 168,
      'calories_est': 1000.0,
      'source': 'gps',
      'type': 'outdoor',
    };

    final summary = runSummaryFromRow(row);

    expect(summary.distanceMeters, 15000);
    expect(summary.duration, const Duration(seconds: 5400));
    expect(summary.avgPaceSecondsPerKm, 360);
    expect(summary.elevationGainMeters, 145);
    expect(summary.avgHr, 150);
    expect(summary.maxHr, 168);
    expect(summary.caloriesEst, 1000);
    expect(summary.type, 'outdoor');
    expect(
      summary.startedAt.toUtc().toIso8601String(),
      startsWith('2026-07-07T17:08:54'),
    );
    expect(summary.hasRoute, isFalse); // no points passed to the list mapper
  });

  test('runSummaryFromRow tolerates absent optionals (manual run)', () {
    final row = <String, dynamic>{
      'started_at': '2026-07-05T09:00:00+00:00',
      'duration_s': 3450,
      'distance_m': 10000, // integer JSON number, not double
      'avg_pace_s_per_km': null,
      'elevation_gain_m': null,
      'avg_hr': null,
      'max_hr': null,
      'calories_est': null,
      'type': 'manual',
    };

    final summary = runSummaryFromRow(row);

    expect(summary.distanceMeters, 10000.0);
    expect(summary.avgPaceSecondsPerKm, isNull);
    expect(summary.avgHr, isNull);
    expect(summary.caloriesEst, isNull);
    expect(summary.type, 'manual');
  });

  test('runPointFromRow maps a trace point', () {
    final point = runPointFromRow(<String, dynamic>{
      'run_id': 'seed-run-02',
      'seq': 0,
      'lat': 51.545,
      'lng': -0.15,
      'altitude_m': 40.0,
      'accuracy_m': 5.0,
      'recorded_at': '2026-07-07T17:08:54+00:00',
    });

    expect(point.latitude, 51.545);
    expect(point.longitude, -0.15);
    expect(point.accuracyMeters, 5);
    expect(point.altitudeMeters, 40);
  });

  test('runSplitFromRow maps a split', () {
    final split = runSplitFromRow(<String, dynamic>{
      'seq': 3,
      'distance_m': 1000.0,
      'duration_s': 322,
      'avg_hr': 149,
    });

    expect(split.index, 3);
    expect(split.distanceMeters, 1000);
    expect(split.duration, const Duration(seconds: 322));
    expect(split.avgHr, 149);
  });
}
