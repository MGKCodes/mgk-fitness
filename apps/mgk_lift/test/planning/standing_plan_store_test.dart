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
      ),
    ],
  },
);

void main() {
  // What a session did to a slot is not recorded here any more: it is read off
  // the log (slot_history_test.dart, #4).

  test('replacing swaps what is live', () async {
    final store = InMemoryStandingPlanStore();
    expect(await store.active(), isNull);

    await store.replace(plan());
    expect((await store.active())!.id, 'p1');
    expect(store.calls, contains('replace:p1'));
  });
}
