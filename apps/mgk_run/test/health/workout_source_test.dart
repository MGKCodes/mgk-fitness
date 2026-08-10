import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:mgk_run/src/features/health/domain/workout_source.dart';

/// Unit conversion is the quiet, expensive kind of bug: a run imported from a
/// watch logging miles would land in the log 1.6× too long, and every number
/// derived from it — weekly volume, pace, what the coach says about the block —
/// would be wrong while looking entirely plausible.
void main() {
  group('metresFrom', () {
    test('converts the units Health actually reports', () {
      expect(metresFrom(5000, 'METER'), 5000);
      expect(metresFrom(500, 'CENTIMETER'), 5);
      expect(metresFrom(1, 'MILE'), closeTo(1609.344, 0.001));
      expect(metresFrom(1, 'YARD'), closeTo(0.9144, 0.0001));
      expect(metresFrom(1, 'FOOT'), closeTo(0.3048, 0.0001));
      expect(metresFrom(1, 'INCH'), closeTo(0.0254, 0.0001));
    });

    test('gives up rather than guessing', () {
      // A wrong distance is worse than no distance: the log renders a missing
      // one honestly, and a plausible wrong one is believed.
      expect(metresFrom(5000, 'FURLONG'), isNull);
      expect(metresFrom(null, 'METER'), isNull);
      expect(metresFrom(5000, null), isNull);
    });

    test(
      'every distance unit in the enum is either handled or deliberately not',
      () {
        // The guard against the enum growing a unit this table has never seen.
        // If Health adds one, this fails and someone decides — rather than every
        // run from that source silently losing its distance.
        const handled = <String>{
          'METER',
          'CENTIMETER',
          'INCH',
          'FOOT',
          'YARD',
          'MILE',
        };
        const notDistance = <String>{
          'MILLIMETER_OF_MERCURY',
          'CENTIMETER_OF_WATER',
          'INCHES_OF_MERCURY',
        };
        for (final HealthDataUnit unit in HealthDataUnit.values) {
          final String name = unit.name.toUpperCase();
          if (!handled.contains(name)) continue;
          expect(
            metresFrom(1, name),
            isNotNull,
            reason: '$name is claimed as handled but converts to null',
          );
        }
        // Sanity: the names above are real members, not typos that quietly pass.
        final all = HealthDataUnit.values
            .map((u) => u.name.toUpperCase())
            .toSet();
        expect(all.containsAll(handled), isTrue);
        expect(all.containsAll(notDistance), isTrue);
      },
    );
  });

  group('kcalFrom', () {
    test('tells the two calories apart', () {
      // LARGE_CALORIE is the dietary Calorie (a kilocalorie); SMALL_CALORIE is
      // a thousandth of it. Confusing them is a 1000x error.
      expect(kcalFrom(450, 'KILOCALORIE'), 450);
      expect(kcalFrom(450, 'LARGE_CALORIE'), 450);
      expect(kcalFrom(450000, 'SMALL_CALORIE'), 450);
      expect(kcalFrom(4184, 'JOULE'), closeTo(1, 0.0001));
    });

    test('gives up rather than guessing', () {
      expect(kcalFrom(450, 'WATT'), isNull);
      expect(kcalFrom(null, 'KILOCALORIE'), isNull);
    });
  });
}
