import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/data/exercise_catalogue.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_template.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_shape.dart';
import 'package:mgk_lift/src/features/planning/domain/training_split.dart';

StandingPlan build({
  int days = 4,
  Equipment kit = Equipment.fullGym,
  Set<String> avoid = const <String>{},
}) {
  final split = TrainingSplit.forDays(days);
  return StandingPlan(
    id: 'p',
    name: split.name,
    dayOrder: split.weekFor(days),
    // Spaced the way somebody would actually train, not Mon-Tue-Wed. The
    // property checks caught this: full body on back-to-back days trains legs
    // and back twice with no day between, which is the thing the recovery rule
    // exists to stop.
    weekdays: _weekdays(days),
    slots: PlanTemplate.slotsFor(
      split: split,
      days: days,
      equipment: kit,
      avoid: avoid,
    ),
  );
}

/// Realistic training days for a given count.
List<int> _weekdays(int days) => switch (days) {
  2 => const <int>[1, 4],
  3 => const <int>[1, 3, 5],
  4 => const <int>[1, 2, 4, 5],
  5 => const <int>[1, 2, 3, 4, 5],
  _ => const <int>[1, 2, 3, 4, 5, 6],
};

void main() {
  test('every movement the template can name is in the catalogue', () {
    // A plan naming a movement the catalogue does not have renders a
    // placeholder thumbnail and breaks the swap, which reads as the app being
    // broken rather than as a typo. Half of the first draft was wrong.
    final known = exerciseCatalogue.map((e) => e.name).toSet();
    for (final days in <int>[2, 3, 4, 5, 6]) {
      for (final kit in Equipment.values) {
        final plan = build(days: days, kit: kit);
        for (final s in plan.slots.values.expand((x) => x)) {
          expect(
            known,
            contains(s.movement),
            reason: '$days days on ${kit.name} named ${s.movement}',
          );
        }
      }
    }
  });

  test('the fallback plan passes the property checks at every day count', () {
    // The template is the floor now, not the product -- what it has to clear is
    // PlanShape, which judges what a plan DOES rather than recognising a shape
    // off a list. If the floor cannot clear the bar, the bar is wrong.
    for (final days in <int>[2, 3, 4, 5, 6]) {
      expect(
        PlanShape.violations(build(days: days)),
        isEmpty,
        reason: '\$days days',
      );
    }
  });

  test('a full-gym day is five or six movements', () {
    // Enough volume to matter, and under the count people quietly start
    // cutting short.
    final plan = build();
    for (final day in plan.slots.entries) {
      expect(day.value.length, inInclusiveRange(4, 6), reason: day.key);
    }
  });

  test('every day leads with a main lift', () {
    final plan = build();
    for (final day in plan.slots.entries) {
      expect(day.value.first.isMain, isTrue, reason: day.key);
    }
  });

  test('an injury is avoided by ROLE, not by movement name', () {
    // "Left shoulder on pressing" has to rule out overhead work whatever it is
    // called this month. Matching names would drop one barbell and leave the
    // dumbbell version in.
    final plan = build(avoid: const <String>{'vertical press'});
    final roles = plan.slots.values.expand((s) => s).map((s) => s.role);
    expect(roles, isNot(contains('vertical press')));
    expect(roles, contains('horizontal press'));
  });

  test('less kit means different movements, not missing days', () {
    final home = build(kit: Equipment.homeWeights);
    for (final day in home.slots.entries) {
      expect(day.value, isNotEmpty, reason: day.key);
    }
    final movements = home.slots.values.expand((s) => s).map((s) => s.movement);
    expect(movements, isNot(contains('Barbell Bench Press')));
    expect(movements, contains('Dumbbell Bench Press'));
  });

  test('bodyweight-only leaves real gaps rather than inventing movements', () {
    // The catalogue has no bodyweight squat, pike push-up or lateral raise, so
    // those roles genuinely cannot be filled. Recorded as a test because it is
    // a catalogue gap worth noticing when it is closed, not a planning bug.
    final bw = build(kit: Equipment.bodyweight);
    final roles = bw.slots.values.expand((s) => s).map((s) => s.role).toSet();
    expect(roles, isNot(contains('squat')));
    expect(roles, isNot(contains('lateral raise')));
    expect(roles, contains('horizontal press'));
  });

  test('the full-body variants do not repeat one day three times', () {
    // A three-day week that squats heavy every session is not a plan.
    final plan = build(days: 3);
    expect(plan.slots.keys.length, 3);
    final mains = plan.slots.values
        .map((s) => s.firstWhere((x) => x.isMain).role)
        .toSet();
    expect(mains.length, greaterThan(1));
  });
}
