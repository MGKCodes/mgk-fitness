import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_units/mgk_units.dart';

void main() {
  group('Elevation stores metres and converts at display', () {
    test('a foot is exactly 0.3048 m, both ways', () {
      expect(const Elevation.metres(0.3048).feet, closeTo(1, 1e-12));
      expect(Elevation.feet(1).metres, closeTo(0.3048, 1e-12));
    });

    test('a round trip through feet does not drift', () {
      const climb = Elevation.metres(312.5);
      expect(Elevation.feet(climb.feet).metres, closeTo(312.5, 1e-9));
    });

    test('it follows the distance system, because a route has one unit', () {
      // Deliberately no ElevationUnit: nobody measures their route in miles
      // and their climb in metres.
      const climb = Elevation.metres(1000);
      expect(climb.inDisplayUnit(UnitSystem.metric), 1000);
      expect(climb.inDisplayUnit(UnitSystem.imperial), closeTo(3280.84, 0.01));
    });
  });

  group('what reaches a screen', () {
    test('whole units, because the sensor has no more precision than that', () {
      expect(const Elevation.metres(312.4).label(UnitSystem.metric), '312 m');
      expect(const Elevation.metres(312.6).label(UnitSystem.metric), '313 m');
      expect(Elevation.feet(1024.3).label(UnitSystem.imperial), '1024 ft');
    });

    test('the suffix is m or ft, never km or mi', () {
      // The trap this type exists to prevent: elevation is not a distance, and
      // borrowing UnitSystem.distanceSuffix would render climb in kilometres.
      expect(Elevation.suffix(UnitSystem.metric), 'm');
      expect(Elevation.suffix(UnitSystem.imperial), 'ft');
      expect(
        Elevation.suffix(UnitSystem.imperial),
        isNot(UnitSystem.imperial.distanceSuffix),
      );
    });

    test('zero is a real reading, not an absence', () {
      // A flat run climbed nothing. Absence is null, and the two must not be
      // rendered the same way (CLAUDE.md rule 6).
      expect(Elevation.zero.label(UnitSystem.metric), '0 m');
    });
  });

  group('arithmetic happens in metres', () {
    test('climbs add', () {
      expect(
        (const Elevation.metres(120) + const Elevation.metres(80)).metres,
        200,
      );
    });

    test('two elevations compare and equate on metres', () {
      expect(const Elevation.metres(100), const Elevation.metres(100));
      expect(Elevation.feet(1000).compareTo(const Elevation.metres(100)), 1);
      expect(
        <Elevation>[const Elevation.metres(30), const Elevation.metres(10)]
          ..sort(),
        <Elevation>[const Elevation.metres(10), const Elevation.metres(30)],
      );
    });
  });
}
