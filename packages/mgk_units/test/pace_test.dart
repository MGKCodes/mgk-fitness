import 'package:test/test.dart';
import 'package:mgk_units/mgk_units.dart';

void main() {
  group('Pace', () {
    test('stores seconds per kilometer', () {
      expect(const Pace.secondsPerKilometer(300).secondsPerKilometer, 300);
    });

    test('derives seconds per mile', () {
      // 5:00 /km is ~8:03 /mi.
      const pace = Pace.secondsPerKilometer(300);
      expect(pace.secondsPerMile, closeTo(482.8032, 1e-3));
    });

    test('constructs from seconds per mile', () {
      final pace = Pace.secondsPerMile(482.8032);
      expect(pace.secondsPerKilometer, closeTo(300, 1e-6));
    });

    test('derives pace from distance and duration', () {
      final pace = Pace.from(
        Distance.kilometers(10),
        const Duration(minutes: 50),
      );
      expect(pace.secondsPerKilometer, closeTo(300, 1e-9));
    });

    test('throws on non-positive distance', () {
      expect(
        () => Pace.from(const Distance.meters(0), const Duration(minutes: 5)),
        throwsArgumentError,
      );
    });

    test('formats as minutes:seconds with a unit suffix', () {
      const pace = Pace.secondsPerKilometer(300);
      expect(pace.format(UnitSystem.metric), '5:00 /km');
      expect(pace.format(UnitSystem.imperial), '8:03 /mi');
    });

    test('rounds to the nearest second when formatting', () {
      expect(
        const Pace.secondsPerKilometer(329).format(UnitSystem.metric),
        '5:29 /km',
      );
      expect(
        const Pace.secondsPerKilometer(329.6).format(UnitSystem.metric),
        '5:30 /km',
      );
    });
  });
}
