import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/units/distance.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';

void main() {
  group('riegelPredict', () {
    test('predicts a 10K from a 5K result', () {
      // 5K in 20:00 -> 10K ~ 1200 * 2^1.06 ~ 2502 s (41:42).
      final t = riegelPredict(
        Distance.kilometers(5),
        const Duration(minutes: 20),
        Distance.kilometers(10),
      );
      expect(t.inSeconds, closeTo(2502, 15));
    });

    test('is the identity for the same distance', () {
      final t = riegelPredict(
        Distance.kilometers(5),
        const Duration(minutes: 20),
        Distance.kilometers(5),
      );
      expect(t.inSeconds, closeTo(1200, 1));
    });

    test('a longer target predicts a slower average pace', () {
      const time = Duration(minutes: 20);
      final tenK = riegelPredict(
        Distance.kilometers(5),
        time,
        Distance.kilometers(10),
      );
      // 10K time is more than double the 5K time (pace slows with distance).
      expect(tenK.inSeconds, greaterThan(time.inSeconds * 2));
    });
  });

  group('TrainingPaces.fromRace', () {
    final paces = TrainingPaces.fromRace(
      Distance.kilometers(5),
      const Duration(minutes: 20),
    );

    test('threshold is slower than 5K race pace', () {
      // 5K in 20:00 is 4:00/km; threshold should be slower (higher s/km).
      expect(paces.thresholdSecondsPerKm, greaterThan(240));
      expect(paces.thresholdSecondsPerKm, lessThan(300)); // ~4:18/km
    });

    test('zones are strictly ordered slow -> fast', () {
      expect(
        paces.recovery.secondsPerKilometer,
        greaterThan(paces.easy.secondsPerKilometer),
      );
      expect(
        paces.easy.secondsPerKilometer,
        greaterThan(paces.marathon.secondsPerKilometer),
      );
      expect(
        paces.marathon.secondsPerKilometer,
        greaterThan(paces.threshold.secondsPerKilometer),
      );
      expect(
        paces.threshold.secondsPerKilometer,
        greaterThan(paces.interval.secondsPerKilometer),
      );
    });

    test('threshold zone equals the derived threshold pace', () {
      expect(
        paces.threshold.secondsPerKilometer,
        closeTo(paces.thresholdSecondsPerKm, 0.001),
      );
    });

    test('rejects a non-positive race', () {
      expect(
        () => TrainingPaces.fromRace(
          Distance.meters(0),
          const Duration(minutes: 20),
        ),
        throwsArgumentError,
      );
    });
  });
}
