import 'package:mgk_units/mgk_units.dart';
import 'package:test/test.dart';

void main() {
  group('canonical storage', () {
    test('a pound is 0.45359237 kg, exactly', () {
      expect(Mass.pounds(1).kilograms, closeTo(0.45359237, 1e-12));
    });

    test('kilograms round-trip through pounds', () {
      expect(Mass.kilograms(100).pounds, closeTo(220.462262, 1e-6));
      expect(Mass.pounds(225).kilograms, closeTo(102.058283, 1e-6));
    });

    test('reading a typed value respects the unit it was typed in', () {
      expect(Mass.inUnit(100, MassUnit.kilograms).kilograms, 100);
      expect(
        Mass.inUnit(100, MassUnit.pounds).kilograms,
        closeTo(45.359237, 1e-6),
      );
    });
  });

  group('display', () {
    test('a bar loaded to 225 lb reads as 225, not 220.5', () {
      // The whole reason displayValue exists. Plates are discrete and the
      // conversion is not.
      final bar = Mass.kilograms(102.058283); // 225 lb exactly
      expect(bar.displayValue(MassUnit.pounds), 225);
      expect(bar.label(MassUnit.pounds), '225 lb');
    });

    test('metric snaps to the half kilo', () {
      expect(Mass.kilograms(62.3).displayValue(MassUnit.kilograms), 62.5);
      expect(Mass.kilograms(62.1).displayValue(MassUnit.kilograms), 62.0);
    });

    test('a trailing .0 is dropped, because nobody writes it', () {
      expect(Mass.kilograms(100).label(MassUnit.kilograms), '100 kg');
      expect(Mass.kilograms(62.5).label(MassUnit.kilograms), '62.5 kg');
    });

    test('inDisplayUnit is exact; displayValue is the rounded one', () {
      final m = Mass.kilograms(100);
      expect(m.inDisplayUnit(MassUnit.pounds), closeTo(220.462, 0.001));
      expect(m.displayValue(MassUnit.pounds), 220);
    });

    test('switching units shows the nearest loadable weight, then settles', () {
      // The accepted trade, stated as a test. 100 kg shows as 220 lb; the next
      // weight the lifter enters is a whole pound value, stored exactly.
      final logged = Mass.kilograms(100);
      expect(logged.displayValue(MassUnit.pounds), 220);

      final reEntered = Mass.inUnit(220, MassUnit.pounds);
      expect(reEntered.displayValue(MassUnit.pounds), 220);
      expect(reEntered.kilograms, closeTo(99.79, 0.01));
    });
  });

  group('arithmetic stays in kilograms', () {
    test('volume is summed canonically, never in display units', () {
      // Round at the edge, add in kilograms. Summing rounded pounds and
      // converting back is how a total drifts away from its parts.
      final sets = <Mass>[
        Mass.kilograms(100),
        Mass.kilograms(100),
        Mass.kilograms(102.5),
      ];
      final total = sets.reduce((a, b) => a + b);
      expect(total.kilograms, 302.5);
    });

    test('a set is weight times reps', () {
      expect((Mass.kilograms(60) * 8).kilograms, 480);
    });

    test('masses compare and sort by their canonical value', () {
      final ordered = <Mass>[
        Mass.pounds(225),
        Mass.kilograms(60),
        Mass.pounds(135),
      ]..sort();
      expect(ordered.first.kilograms, 60);
      expect(ordered.last.displayValue(MassUnit.pounds), 225);
    });
  });

  group('distance and mass are chosen independently', () {
    test('miles with kilograms is a legal, ordinary combination', () {
      // The correction that prompted splitting these: a single metric/imperial
      // switch could not express what British gyms and British roads actually
      // do. core.user_settings has always had two columns.
      const distance = UnitSystem.imperial;
      const mass = MassUnit.kilograms;

      expect(
        Distance.kilometers(5).inDisplayUnit(distance),
        closeTo(3.107, 0.001),
      );
      expect(Mass.kilograms(100).label(mass), '100 kg');
    });

    test('kilometres with pounds is equally legal', () {
      expect(Distance.kilometers(5).inDisplayUnit(UnitSystem.metric), 5);
      expect(Mass.kilograms(102.058283).label(MassUnit.pounds), '225 lb');
    });
  });

  group('reading the stored preferences', () {
    test('distance_unit maps to a distance unit only', () {
      expect(UnitSystem.fromStored('km'), UnitSystem.metric);
      expect(UnitSystem.fromStored('mi'), UnitSystem.imperial);
    });

    test('a weight value reaching the distance setting is not honoured', () {
      // 'lbs' here means something upstream crossed the two settings over.
      // Reading it as miles would hide that; metric is the safe default.
      expect(UnitSystem.fromStored('lbs'), UnitSystem.metric);
    });

    test('weight_unit maps to a mass unit', () {
      expect(MassUnit.fromStored('kg'), MassUnit.kilograms);
      expect(MassUnit.fromStored('lbs'), MassUnit.pounds);
    });

    test('anything unrecognised falls back rather than guessing', () {
      // Most accounts have no settings row at all — 5 of 12 at the time of
      // writing — so null is the common case, not an error.
      expect(UnitSystem.fromStored(null), UnitSystem.metric);
      expect(MassUnit.fromStored(null), MassUnit.kilograms);
      expect(MassUnit.fromStored('stone'), MassUnit.kilograms);
    });

    test('storedValue round-trips through the settings column', () {
      for (final u in MassUnit.values) {
        expect(MassUnit.fromStored(u.storedValue), u);
      }
      for (final u in UnitSystem.values) {
        expect(UnitSystem.fromStored(u.storedValue), u);
      }
    });
  });
}
