import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/stats/domain/working_weights.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_units/mgk_units.dart';

final DateTime now = DateTime(2026, 10, 12);

Session bench(DateTime day, double kg, int reps) => Session(
  id: day.toIso8601String(),
  name: 'Push',
  startedAt: day,
  endedAt: day.add(const Duration(hours: 1)),
  exercises: <SessionExercise>[
    SessionExercise(
      id: 'e',
      name: 'Barbell Bench Press',
      orderIndex: 0,
      sets: <SessionSet>[
        SessionSet(
          id: 's',
          setNumber: 1,
          weightKg: kg,
          reps: reps,
          isCompleted: true,
        ),
      ],
    ),
  ],
);

WorkingWeights? of(
  List<Session> log, {
  String? kit = 'Barbell',
  MassUnit unit = MassUnit.kilograms,
}) => WorkingWeights.of(
  log,
  'Barbell Bench Press',
  now: now,
  unit: unit,
  kit: kit,
);

void main() {
  test('the issue\'s worked example: 100 kg estimated', () {
    // 100 × 1 is an estimate of exactly 100, which makes the bands checkable
    // by hand: 100 / (1 + (reps + 1) / 30), floored to 2.5.
    final w = of(<Session>[bench(now, 100, 1)])!;
    String band(int i) =>
        '${w.bands[i].low.kilograms}–${w.bands[i].high.kilograms}';
    expect(band(0), '80.0–85.0'); // 81.1 and 85.7
    expect(band(1), '70.0–77.5'); // 71.4 and 78.9
    expect(band(2), '62.5–67.5'); // 63.8 and 69.8
    expect(w.bands.map((b) => b.range), RepRange.values);
    expect(w.bands[2].range.isRough, isTrue);
    expect(w.bands[0].range.isRough, isFalse);
  });

  test('the ranges do not overlap', () {
    // 7–12 / 12–16 put a set of twelve in two bands.
    for (var i = 1; i < RepRange.values.length; i++) {
      expect(RepRange.values[i].min, RepRange.values[i - 1].max + 1);
    }
  });

  test('every band is a weight the kit has, never above the formula', () {
    for (final (kit, step) in <(String?, double)>[
      ('Barbell', 2.5),
      ('EZ Bar', 2.5),
      ('Dumbbell', 2),
      ('Cable', 5),
      ('Machine', 5),
      (null, 2.5),
    ]) {
      final w = of(<Session>[bench(now, 87, 7)], kit: kit)!;
      final oneRm = 87 * (1 + 7 / 30);
      for (final b in w.bands) {
        for (final (weight, reps) in <(Mass, int)>[
          (b.low, b.range.max),
          (b.high, b.range.min),
        ]) {
          final kg = weight.kilograms;
          expect(kg % step, closeTo(0, 1e-9), reason: '$kit $kg');
          expect(kg, lessThanOrEqualTo(oneRm / (1 + (reps + 1) / 30)));
          expect(kg, greaterThan(oneRm / (1 + (reps + 1) / 30) - step));
        }
      }
    }
  });

  test('pounds step in pounds', () {
    expect(loadStep('Barbell', MassUnit.pounds), 5);
    expect(loadStep('Dumbbell', MassUnit.pounds), 5);
    expect(loadStep('Cable', MassUnit.pounds), 10);
    final w = of(<Session>[
      bench(now, Mass.pounds(225).kilograms, 5),
    ], unit: MassUnit.pounds)!;
    for (final b in w.bands) {
      final plates = b.high.pounds / 5;
      expect(plates, closeTo(plates.roundToDouble(), 1e-6));
    }
  });

  test('the same weight at both ends is one weight', () {
    // A light cable movement: 4–6 comes out at 17.5 and 18.5, both 15 on a
    // 5 kg stack.
    final w = of(<Session>[bench(now, 18, 6)], kit: 'Cable')!;
    expect(w.bands.first.isSingle, isTrue);
    expect(w.bands.first.high.kilograms, 15);
  });

  test('a band too light to load is left out', () {
    // 6 kg for eight on a 5 kg stack: 12–16 is under one plate.
    final w = of(<Session>[bench(now, 6, 8)], kit: 'Cable');
    expect(w?.bands.map((b) => b.range), isNot(contains(RepRange.endurance)));
  });

  group('the set they come from', () {
    test('is the best estimate of the last six weeks', () {
      final w = of(<Session>[
        bench(now.subtract(const Duration(days: 60)), 140, 3),
        bench(now.subtract(const Duration(days: 20)), 100, 5),
        bench(now.subtract(const Duration(days: 3)), 102.5, 3),
      ])!;
      // 140 × 3 is the bigger number, and two months old.
      expect(w.from.weight.kilograms, 100);
      expect(w.from.reps, 5);
    });

    test('counts nothing over twelve reps', () {
      expect(of(<Session>[bench(now, 60, 15)]), isNull);
    });

    test('is nothing with no weight on it', () {
      expect(of(<Session>[bench(now, 0, 8)]), isNull);
    });

    test('is nothing at all, and so are the bands', () {
      expect(of(const <Session>[]), isNull);
    });
  });
}
