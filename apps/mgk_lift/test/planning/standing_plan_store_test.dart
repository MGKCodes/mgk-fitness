import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan_store.dart';
import 'package:mgk_lift/src/features/planning/domain/training_split.dart';

StandingPlan plan() => StandingPlan(
  id: 'p1',
  split: TrainingSplit.upperLower,
  weekdays: const <int>[1, 2, 4, 5],
  slots: <String, List<MovementSlot>>{
    'Upper': <MovementSlot>[
      const MovementSlot(
        id: 'u1',
        role: 'horizontal press',
        movement: 'Barbell Bench Press',
        isMain: true,
        lastTopKg: 85,
        lastTopReps: 6,
        sessionsAtSameTop: 2,
      ),
    ],
  },
);

void main() {
  group('the split survives a round trip', () {
    test('every split has a wire value and comes back as itself', () {
      for (final s in TrainingSplit.values) {
        expect(TrainingSplitWire.fromWire(s.wire), s, reason: s.name);
      }
    });

    test('the wire value is not the label', () {
      // The label is lifter-facing and will be reworded eventually. If the two
      // were the same string, rewording it would stop every stored row parsing.
      expect(TrainingSplit.pushPullLegs.wire, 'push_pull_legs');
      expect(TrainingSplit.pushPullLegs.name, isNot('push_pull_legs'));
    });

    test('an unknown split loads as full body rather than throwing', () {
      // A plan that will not load is worse than one that loads as three
      // full-body days, and the day count corrects it on the next save.
      expect(TrainingSplitWire.fromWire('nonsense'), TrainingSplit.fullBody);
    });
  });

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
