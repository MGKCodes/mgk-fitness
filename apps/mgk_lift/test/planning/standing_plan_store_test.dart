import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan_store.dart';

StandingPlan plan() => StandingPlan(
  id: 'p1',
  name: 'Upper / Lower',
  dayOrder: const <String>['Upper', 'Lower', 'Upper', 'Lower'],
  weekdays: const <int>[1, 2, 4, 5],
  slots: <String, List<MovementSlot>>{
    'Upper': <MovementSlot>[
      const MovementSlot(
        id: 'u1',
        role: 'horizontal press',
        movement: 'Barbell Bench Press',
        isMain: true,
        sets: 4,
        reps: 6,
        lastTopKg: 85,
        lastTopReps: 6,
        sessionsAtSameTop: 2,
      ),
    ],
  },
);

void main() {
  group('recording what a session did', () {
    test('an improvement resets the stall counter', () async {
      final store = InMemoryStandingPlanStore(plan());
      await store.recordResult('u1', topKg: 87.5, reps: 6, improved: true);

      final slot = (await store.active())!.slots['Upper']!.single;
      expect(slot.lastTopKg, 87.5);
      expect(slot.sessionsAtSameTop, 0);
    });

    test('holding increments it', () async {
      // That counter is the whole rotation trigger, so getting it backwards
      // would either rotate everything or nothing.
      final store = InMemoryStandingPlanStore(plan());
      await store.recordResult('u1', topKg: 85, reps: 6, improved: false);

      final slot = (await store.active())!.slots['Upper']!.single;
      expect(slot.sessionsAtSameTop, 3);
    });

    test('a result for an unknown slot changes nothing', () async {
      final store = InMemoryStandingPlanStore(plan());
      await store.recordResult('nope', topKg: 100, reps: 1, improved: true);

      final slot = (await store.active())!.slots['Upper']!.single;
      expect(slot.lastTopKg, 85);
      expect(slot.sessionsAtSameTop, 2);
    });
  });

  test('replacing swaps what is live', () async {
    final store = InMemoryStandingPlanStore();
    expect(await store.active(), isNull);

    await store.replace(plan());
    expect((await store.active())!.id, 'p1');
    expect(store.calls, contains('replace:p1'));
  });
}
