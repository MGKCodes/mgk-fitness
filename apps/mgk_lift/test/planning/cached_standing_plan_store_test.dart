import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/data/cached_standing_plan_store.dart';
import 'package:mgk_lift/src/features/planning/domain/coach_planner.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_intake.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan_store.dart';

final StandingPlan plan = StandingPlan(
  id: 'p',
  name: 'Push / Pull / Legs',
  dayOrder: const <String>['Push', 'Pull', 'Legs'],
  weekdays: const <int>[1, 3, 5],
  rationale: 'Three days, one each.',
  startedAt: DateTime.utc(2026, 9, 1),
  slots: const <String, List<MovementSlot>>{
    'Push': <MovementSlot>[
      MovementSlot(
        id: 'a',
        role: 'horizontal press',
        movement: 'Barbell Bench Press',
        isMain: true,
        sets: 4,
        reps: 6,
        sessionsAtSameTop: 2,
        lastTopKg: 92.5,
        lastTopReps: 6,
      ),
    ],
    'Pull': <MovementSlot>[
      MovementSlot(
        id: 'b',
        role: 'row',
        movement: 'Barbell Row',
        sets: 3,
        reps: 8,
      ),
    ],
    'Legs': <MovementSlot>[],
  },
);

/// A server that can be switched off.
class _Remote implements StandingPlanStore {
  StandingPlan? live = plan;
  bool reachable = true;

  @override
  Future<StandingPlan?> active() async {
    if (!reachable) throw const PlanException(PlanFailure.unavailable);
    return live;
  }

  @override
  Future<StandingPlan> replace(StandingPlan p, {PlanIntake? intake}) async =>
      live = p;

  @override
  Future<void> recordResult(
    String slotId, {
    required double topKg,
    required int reps,
    required bool improved,
  }) async {}
}

void main() {
  test('a plan survives the trip to the phone and back, whole', () {
    final back = planFromJson(planToJson(plan));
    expect(back.name, plan.name);
    expect(back.dayOrder, plan.dayOrder);
    expect(back.weekdays, plan.weekdays);
    expect(back.rationale, plan.rationale);
    expect(back.startedAt, plan.startedAt);
    final bench = back.slots['Push']!.single;
    expect(bench.movement, 'Barbell Bench Press');
    expect(bench.isMain, isTrue);
    expect(bench.lastTopKg, 92.5);
    expect(bench.sessionsAtSameTop, 2);
    expect(back.slots['Legs'], isEmpty);
    expect(back.dayFor(DateTime(2026, 8, 19)), 'Pull'); // a Wednesday
  });

  test(
    'with no signal, the last plan the server gave is still the plan',
    () async {
      final remote = _Remote();
      final store = CachedStandingPlanStore(
        remote: remote,
        cache: InMemoryPlanCache(),
      );

      expect((await store.active())?.id, 'p');
      remote.reachable = false;
      // The gym, the basement: today's session is still on Track.
      final offline = await store.active();
      expect(offline?.name, 'Push / Pull / Legs');
      expect(offline?.slots['Push']!.single.lastTopKg, 92.5);
    },
  );

  test('no plan on the server clears the copy', () async {
    final remote = _Remote();
    final cache = InMemoryPlanCache();
    final store = CachedStandingPlanStore(remote: remote, cache: cache);
    await store.active();

    remote.live = null;
    expect(await store.active(), isNull);
    remote.reachable = false;
    // Nothing left to fall back on: a session nobody is following stays off
    // Track.
    expect(await store.active(), isNull);
  });

  test('a copy nobody can read is no copy', () async {
    final remote = _Remote()..reachable = false;
    final store = CachedStandingPlanStore(
      remote: remote,
      cache: InMemoryPlanCache('{not json'),
    );
    expect(await store.active(), isNull);
  });

  test('a replacement is saved from the server\'s reply', () async {
    final remote = _Remote();
    final store = CachedStandingPlanStore(
      remote: remote,
      cache: InMemoryPlanCache(),
    );
    final next = StandingPlan(
      id: 'q',
      name: 'Upper / Lower',
      dayOrder: const <String>['Upper', 'Lower'],
      weekdays: const <int>[2, 4],
      slots: const <String, List<MovementSlot>>{},
    );
    await store.replace(next);
    remote.reachable = false;
    expect((await store.active())?.name, 'Upper / Lower');
  });
}
