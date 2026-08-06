import 'package:test/test.dart';
import 'package:mgk_units/mgk_units.dart';

void main() {
  group('Distance', () {
    test('stores its canonical value in meters', () {
      expect(const Distance.meters(5000).meters, 5000);
    });

    test('constructs from kilometers', () {
      expect(Distance.kilometers(5).meters, 5000);
    });

    test('constructs from miles using the exact mile', () {
      expect(Distance.miles(1).meters, closeTo(1609.344, 1e-9));
    });

    test('derives kilometers and miles on demand', () {
      const d = Distance.meters(1609.344);
      expect(d.kilometers, closeTo(1.609344, 1e-9));
      expect(d.miles, closeTo(1, 1e-9));
    });

    test('inDisplayUnit follows the unit system', () {
      final d = Distance.kilometers(10);
      expect(d.inDisplayUnit(UnitSystem.metric), closeTo(10, 1e-9));
      expect(d.inDisplayUnit(UnitSystem.imperial), closeTo(6.2137119, 1e-6));
    });

    test('formats for display', () {
      final d = Distance.kilometers(5);
      expect(d.format(UnitSystem.metric), '5.00 km');
      expect(d.format(UnitSystem.imperial), '3.11 mi');
      expect(d.format(UnitSystem.metric, fractionDigits: 0), '5 km');
    });

    test('supports arithmetic and comparison', () {
      expect(
        Distance.kilometers(3) + Distance.kilometers(2),
        Distance.kilometers(5),
      );
      expect(
        Distance.kilometers(3) - Distance.kilometers(2),
        Distance.kilometers(1),
      );
      expect(Distance.kilometers(3) > Distance.kilometers(2), isTrue);

      final list = [
        Distance.kilometers(3),
        Distance.kilometers(1),
        Distance.kilometers(2),
      ]..sort();
      expect(list.map((d) => d.kilometers), [1, 2, 3]);
    });

    test('has value equality', () {
      expect(Distance.kilometers(5), const Distance.meters(5000));
      expect(
        Distance.kilometers(5).hashCode,
        const Distance.meters(5000).hashCode,
      );
    });
  });
}
