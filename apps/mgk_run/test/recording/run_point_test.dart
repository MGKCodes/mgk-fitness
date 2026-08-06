import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';

void main() {
  group('RunPoint', () {
    final timestamp = DateTime.utc(2026, 1, 1, 12);

    RunPoint make() => RunPoint(
      latitude: 51.5,
      longitude: -0.12,
      accuracyMeters: 5,
      altitudeMeters: 42,
      timestamp: timestamp,
    );

    test('allows a null altitude', () {
      final point = RunPoint(
        latitude: 1,
        longitude: 2,
        accuracyMeters: 5,
        timestamp: timestamp,
      );
      expect(point.altitudeMeters, isNull);
    });

    test('has value equality over all fields', () {
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
    });

    test('differs when any field differs', () {
      final other = RunPoint(
        latitude: 51.5,
        longitude: -0.12,
        accuracyMeters: 9,
        altitudeMeters: 42,
        timestamp: timestamp,
      );
      expect(make(), isNot(other));
    });
  });
}
