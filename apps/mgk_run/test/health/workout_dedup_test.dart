import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/health/domain/health_workout.dart';
import 'package:mgk_run/src/features/health/domain/workout_dedup.dart';

HealthWorkout _w(
  String source,
  int startMinute,
  int durationMinutes, {
  double? distanceMeters,
}) => HealthWorkout(
  sourceBundleId: source,
  start: DateTime(2026, 1, 1, 8, startMinute),
  end: DateTime(2026, 1, 1, 8, startMinute + durationMinutes),
  distanceMeters: distanceMeters,
);

/// The preferred source is the app's OWN bundle identifier, which is what
/// HKSource reports. If that constant and the shipped id ever disagree, every
/// one of this app's workouts reads as a stranger's and quietly loses to the
/// watch's copy — taking the GPS trace with it.
void main() {
  const watch = 'com.apple.health.watch';
  const thirdParty = 'com.thirdparty.app';

  test('same run from watch + Runio + a third app collapses to one', () {
    final result = dedupeWorkouts(<HealthWorkout>[
      _w(watch, 0, 30, distanceMeters: 5000),
      _w(ownSourceBundleId, 0, 30, distanceMeters: 5010),
      _w(thirdParty, 1, 29, distanceMeters: 4990),
    ]);

    expect(result, hasLength(1));
    expect(result.single.sourceBundleId, ownSourceBundleId);
  });

  test('distinct runs hours apart are both kept', () {
    final result = dedupeWorkouts(<HealthWorkout>[
      _w(ownSourceBundleId, 0, 30, distanceMeters: 5000),
      _w(ownSourceBundleId, 120, 25, distanceMeters: 4000),
    ]);

    expect(result, hasLength(2));
  });

  test('a small start-time skew between devices still merges', () {
    final result = dedupeWorkouts(<HealthWorkout>[
      _w(ownSourceBundleId, 0, 30, distanceMeters: 5000),
      HealthWorkout(
        sourceBundleId: watch,
        start: DateTime(2026, 1, 1, 8, 0, 20), // 20s later
        end: DateTime(2026, 1, 1, 8, 30, 10),
        distanceMeters: 4990,
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.sourceBundleId, ownSourceBundleId);
  });

  test('without a Runio recording, the source with distance wins', () {
    final result = dedupeWorkouts(<HealthWorkout>[
      _w(watch, 0, 30), // no distance
      _w(thirdParty, 0, 30, distanceMeters: 5000),
    ], preferredSourceBundleId: 'com.nonexistent');

    expect(result, hasLength(1));
    expect(result.single.distanceMeters, 5000);
  });

  test('an empty input yields an empty list', () {
    expect(dedupeWorkouts(const <HealthWorkout>[]), isEmpty);
  });
}
