import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan.dart';

MovementSlot slot(
  String role,
  String movement, {
  bool main = false,
  int stale = 0,
}) => MovementSlot(
  id: role,
  role: role,
  movement: movement,
  isMain: main,
  sets: 3,
  reps: 10,
  sessionsAtSameTop: stale,
);

StandingPlan fourDay({Map<String, List<MovementSlot>>? slots}) => StandingPlan(
  id: 'p',
  name: 'Upper / Lower',
  dayOrder: const <String>['Upper', 'Lower', 'Upper', 'Lower'],
  // Mon, Tue, Thu, Fri.
  weekdays: const <int>[1, 2, 4, 5],
  slots: slots ?? const <String, List<MovementSlot>>{},
);

void main() {
  group('the week is derived, not scheduled', () {
    test('each training weekday maps to its day of the split', () {
      final p = fourDay();
      expect(p.dayFor(DateTime(2026, 8, 17)), 'Upper'); // Monday
      expect(p.dayFor(DateTime(2026, 8, 18)), 'Lower'); // Tuesday
      expect(p.dayFor(DateTime(2026, 8, 20)), 'Upper'); // Thursday
      expect(p.dayFor(DateTime(2026, 8, 21)), 'Lower'); // Friday
    });

    test('a day off the plan is a rest day, not a gap', () {
      expect(fourDay().dayFor(DateTime(2026, 8, 19)), isNull); // Wednesday
    });

    test('missing a fortnight does not put you behind', () {
      // The whole reason this is derived from the weekday. A pre-generated
      // schedule would have three sessions owing and a plan that moved on
      // without you; here the next Monday is still Upper.
      final p = fourDay();
      expect(p.dayFor(DateTime(2026, 8, 17)), 'Upper');
      expect(p.dayFor(DateTime(2026, 8, 31)), 'Upper');
    });

    test('nothing expires, because there is no end to expire against', () {
      final p = fourDay();
      // A year out, and it still answers.
      expect(p.dayFor(DateTime(2027, 8, 16)), 'Upper');
    });
  });

  group('rotation', () {
    test('an accessory that has not moved in six sessions is eligible', () {
      final p = fourDay(
        slots: <String, List<MovementSlot>>{
          'Upper': <MovementSlot>[
            slot(
              'horizontal press',
              'Barbell Bench Press',
              main: true,
              stale: 9,
            ),
            slot('lateral raise', 'Cable Lateral Raise', stale: 6),
            slot('vertical pull', 'Lat Pulldown', stale: 2),
          ],
        },
      );
      expect(p.stalled.map((s) => s.role), <String>['lateral raise']);
    });

    test('a main lift is never rotated for stalling', () {
      // A stalled squat is a programming problem -- load, fatigue, sleep --
      // and swapping the movement hides it rather than fixing it.
      expect(
        slot('squat', 'Barbell Back Squat', main: true, stale: 20).hasStalled,
        isFalse,
      );
    });

    test('five sessions is not yet a stall', () {
      // Long enough to rule out a bad week, an illness, a deliberately light day.
      expect(slot('curl', 'Dumbbell Curl', stale: 5).hasStalled, isFalse);
      expect(slot('curl', 'Dumbbell Curl', stale: 6).hasStalled, isTrue);
    });
  });
}
