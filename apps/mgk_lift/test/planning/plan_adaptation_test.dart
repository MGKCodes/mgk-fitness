import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/plan.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_adaptation.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_validator.dart';
import 'package:mgk_units/mgk_units.dart';

PlanSession session(
  int weekday, {
  PlanSessionStatus status = PlanSessionStatus.planned,
  List<PlannedMovement>? movements,
}) => PlanSession(
  id: 'w1-d$weekday',
  weekNumber: 1,
  weekday: weekday,
  // 2026-08-10 is a Monday, so weekday n is the 9th + n.
  scheduledDate: DateTime(2026, 8, 9 + weekday),
  kind: weekday == 1 ? 'push' : 'pull',
  status: status,
  movements:
      movements ??
      <PlannedMovement>[
        const PlannedMovement(
          name: 'Barbell Bench Press',
          sets: 3,
          reps: 5,
          target: Mass.kilograms(85),
        ),
        const PlannedMovement(name: 'Cable Fly', sets: 3, reps: 12),
      ],
);

Plan planWith(List<PlanSession> sessions) => Plan(
  id: 'p1',
  startDate: DateTime(2026, 8, 10),
  weeks: 8,
  status: PlanStatus.active,
  profile: const PlanProfile(daysPerWeek: 2, availableWeekdays: <int>[1, 4, 5]),
  arc: const <PlanWeek>[PlanWeek(number: 1, phase: PlanPhase.build)],
  sessions: sessions,
);

AdaptProposal proposal(List<Map<String, Object?>> changes) =>
    AdaptProposal.fromJson(<String, Object?>{
      'reply': 'Here is what I would change.',
      'changes': changes,
    });

const adapter = PlanAdapter();

void main() {
  group('what the coach may change', () {
    test('moving a session onto a free training day is allowed', () {
      final plan = planWith(<PlanSession>[session(1), session(4)]);
      final kept = adapter.check(
        proposal(<Map<String, Object?>>[
          <String, Object?>{
            'action': 'move',
            'weekday': 4,
            'to_weekday': 5,
            'movement': null,
            'to': null,
            'why': 'Gives the shoulder another day',
          },
        ]),
        plan: plan,
        weekNumber: 1,
      );

      expect(kept, hasLength(1));
      expect(kept.single.label, 'Move Pull to Friday');

      final after = adapter.apply(plan, kept);
      final moved = after.sessions.firstWhere((s) => s.id == 'w1-d4');
      expect(moved.weekday, 5);
      expect(moved.scheduledDate, DateTime(2026, 8, 14));
    });

    test('a session already trained is not the coach\'s to edit', () {
      // It happened. Editing it would make the log disagree with what they did,
      // which is worse than refusing the change.
      final plan = planWith(<PlanSession>[
        session(1, status: PlanSessionStatus.completed),
        session(4),
      ]);
      final kept = adapter.check(
        proposal(<Map<String, Object?>>[
          <String, Object?>{
            'action': 'lighten',
            'weekday': 1,
            'to_weekday': null,
            'movement': null,
            'to': null,
            'why': 'You said you were sore',
          },
        ]),
        plan: plan,
        weekNumber: 1,
      );
      expect(kept, isEmpty);
    });

    test('a move onto a day they do not train is dropped', () {
      final plan = planWith(<PlanSession>[session(1), session(4)]);
      final kept = adapter.check(
        proposal(<Map<String, Object?>>[
          <String, Object?>{
            'action': 'move',
            'weekday': 4,
            'to_weekday': 3,
            'movement': null,
            'to': null,
            'why': 'Wednesday',
          },
        ]),
        plan: plan,
        weekNumber: 1,
      );
      expect(kept, isEmpty);
    });

    test('a move onto a day already taken is dropped', () {
      final plan = planWith(<PlanSession>[session(1), session(4)]);
      final kept = adapter.check(
        proposal(<Map<String, Object?>>[
          <String, Object?>{
            'action': 'move',
            'weekday': 4,
            'to_weekday': 1,
            'movement': null,
            'to': null,
            'why': 'Onto Monday',
          },
        ]),
        plan: plan,
        weekNumber: 1,
      );
      expect(kept, isEmpty);
    });

    test('swapping a movement the session does not have is dropped', () {
      final plan = planWith(<PlanSession>[session(1), session(4)]);
      final kept = adapter.check(
        proposal(<Map<String, Object?>>[
          <String, Object?>{
            'action': 'swap_movement',
            'weekday': 1,
            'to_weekday': null,
            'movement': 'Barbell Squat',
            'to': 'Leg Press',
            'why': 'Not in it',
          },
        ]),
        plan: plan,
        weekNumber: 1,
      );
      expect(kept, isEmpty);
    });

    test('one bad change does not take the good ones with it', () {
      // Same trade as a mid-session swap: the reply is the valuable part, and
      // refusing everything because one suggestion named a day they do not
      // train would be the worst reading of "the validator disposes".
      final plan = planWith(<PlanSession>[session(1), session(4)]);
      final kept = adapter.check(
        proposal(<Map<String, Object?>>[
          <String, Object?>{
            'action': 'move',
            'weekday': 4,
            'to_weekday': 3,
            'movement': null,
            'to': null,
            'why': 'Impossible',
          },
          <String, Object?>{
            'action': 'lighten',
            'weekday': 1,
            'to_weekday': null,
            'movement': null,
            'to': null,
            'why': 'Fine',
          },
        ]),
        plan: plan,
        weekNumber: 1,
      );
      expect(kept.map((c) => c.why), <String>['Fine']);
    });

    test('an action nobody defined is dropped, not guessed at', () {
      final plan = planWith(<PlanSession>[session(1)]);
      final kept = adapter.check(
        proposal(<Map<String, Object?>>[
          <String, Object?>{
            'action': 'reschedule_everything',
            'weekday': 1,
            'to_weekday': null,
            'movement': null,
            'to': null,
            'why': 'Invented',
          },
        ]),
        plan: plan,
        weekNumber: 1,
      );
      expect(kept, isEmpty);
    });
  });

  group('applying changes', () {
    test('everything not named is left exactly as it was', () {
      // The whole reason this takes a diff. A regenerated week would rewrite
      // sessions nobody asked about, in this week and every other.
      final plan = planWith(<PlanSession>[
        session(1),
        session(4),
        PlanSession(
          id: 'w2-d1',
          weekNumber: 2,
          weekday: 1,
          scheduledDate: DateTime(2026, 8, 17),
          kind: 'push',
          movements: const <PlannedMovement>[
            PlannedMovement(name: 'Barbell Bench Press', sets: 3, reps: 5),
          ],
        ),
      ]);
      final kept = adapter.check(
        proposal(<Map<String, Object?>>[
          <String, Object?>{
            'action': 'drop',
            'weekday': 4,
            'to_weekday': null,
            'movement': null,
            'to': null,
            'why': 'Away Thursday',
          },
        ]),
        plan: plan,
        weekNumber: 1,
      );

      final after = adapter.apply(plan, kept);
      expect(after.sessions.map((s) => s.id), <String>['w1-d1', 'w2-d1']);
      // Week two is untouched, and so is week one's Monday.
      expect(
        after.sessions
            .firstWhere((s) => s.id == 'w1-d1')
            .movements
            .first
            .target
            ?.kilograms,
        85,
      );
    });

    test('lightening drops a set and eases the load, on their own numbers', () {
      // Arithmetic on figures already derived from their log, done in Dart for
      // the same reason targets are: a model asked to restate a session to make
      // it lighter will change more than it was asked to.
      final plan = planWith(<PlanSession>[session(1)]);
      final kept = adapter.check(
        proposal(<Map<String, Object?>>[
          <String, Object?>{
            'action': 'lighten',
            'weekday': 1,
            'to_weekday': null,
            'movement': null,
            'to': null,
            'why': 'Sore',
          },
        ]),
        plan: plan,
        weekNumber: 1,
      );

      final after = adapter.apply(plan, kept);
      final movements = after.sessions.single.movements;
      expect(movements.first.sets, 2);
      // 85 × 0.9 = 76.5, rounded to a loadable 77.5.
      expect(movements.first.target?.kilograms, 77.5);
      // A movement with no target still has none — nothing is invented on the
      // way past.
      expect(movements.last.target, isNull);
      expect(movements.last.sets, 2);
    });

    test('a swapped-in movement carries no target', () {
      // It is a movement the coach has not seen this lifter do, which is
      // exactly the case the load rule exists for.
      final plan = planWith(<PlanSession>[session(1)]);
      final kept = adapter.check(
        proposal(<Map<String, Object?>>[
          <String, Object?>{
            'action': 'swap_movement',
            'weekday': 1,
            'to_weekday': null,
            'movement': 'Barbell Bench Press',
            'to': 'Dumbbell Bench Press',
            'why': 'Kinder on the shoulder',
          },
        ]),
        plan: plan,
        weekNumber: 1,
      );

      final after = adapter.apply(plan, kept);
      final swapped = after.sessions.single.movements.first;
      expect(swapped.name, 'Dumbbell Bench Press');
      expect(swapped.target, isNull);
      expect(swapped.sets, 3);
    });

    test('dropping removes the session rather than marking it skipped', () {
      // They did not skip it. It was never asked of them.
      final plan = planWith(<PlanSession>[session(1), session(4)]);
      final kept = adapter.check(
        proposal(<Map<String, Object?>>[
          <String, Object?>{
            'action': 'drop',
            'weekday': 1,
            'to_weekday': null,
            'movement': null,
            'to': null,
            'why': 'Away',
          },
        ]),
        plan: plan,
        weekNumber: 1,
      );
      final after = adapter.apply(plan, kept);
      expect(after.sessions.map((s) => s.weekday), <int>[4]);
    });
  });
}
