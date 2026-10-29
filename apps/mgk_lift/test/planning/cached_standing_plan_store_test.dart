import 'dart:convert';

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

/// A server that can be switched off, or slowed to a crawl.
class _Remote implements StandingPlanStore {
  StandingPlan? live = plan;
  bool reachable = true;

  /// How long an answer takes. Null is at once.
  Duration? delay;

  @override
  Future<StandingPlan?> active() async {
    if (delay case final d?) await Future<void>.delayed(d);
    if (!reachable) throw const PlanException(PlanFailure.unavailable);
    return live;
  }

  @override
  Stream<PlanRead> watch() async* {
    yield PlanRead(await active(), freshness: PlanFreshness.checked);
  }

  @override
  Future<StandingPlan> replace(StandingPlan p, {PlanIntake? intake}) async =>
      live = p;
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
    expect(bench.sets, 4);
    expect(bench.reps, 6);
    expect(back.slots['Legs'], isEmpty);
    expect(back.dayFor(DateTime(2026, 8, 19)), 'Pull'); // a Wednesday
  });

  test('a slot\'s history is not saved with it', () {
    // It is read off the log (#4). A copy here could only disagree with it.
    final bench = planFromJson(planToJson(plan)).slots['Push']!.single;
    expect(bench.hasHistory, isFalse);
    expect(bench.sessionsAtSameTop, 0);
  });

  test('a copy saved with history still reads', () {
    // Copies saved before #4 carry it. Ignored, rather than the plan lost.
    final json = planToJson(plan);
    final push = (json['slots']! as Map<String, Object?>)['Push']! as List;
    (push.single as Map<String, Object?>).addAll(<String, Object?>{
      'sessionsAtSameTop': 2,
      'lastTopKg': 92.5,
      'lastTopReps': 6,
    });
    final bench = planFromJson(json).slots['Push']!.single;
    expect(bench.movement, 'Barbell Bench Press');
    expect(bench.hasHistory, isFalse);
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
      expect(offline?.slots['Push']!.single.movement, 'Barbell Bench Press');
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

  group('the saved copy first (#2)', () {
    final at = DateTime(2026, 10, 12, 7, 30);

    test('the copy is shown, then the server\'s answer', () async {
      final remote = _Remote();
      final cache = InMemoryPlanCache();
      await CachedStandingPlanStore(
        remote: remote,
        cache: cache,
        clock: () => at,
      ).active();

      final later = at.add(const Duration(hours: 2));
      final reads = await CachedStandingPlanStore(
        remote: remote,
        cache: cache,
        clock: () => later,
      ).watch().toList();

      expect(reads.map((r) => r.freshness), <PlanFreshness>[
        PlanFreshness.saved,
        PlanFreshness.checked,
      ]);
      // The copy says when it was the server's answer; the answer says now.
      expect(reads.first.checkedAt, at);
      expect(reads.first.plan?.name, 'Push / Pull / Legs');
      expect(reads.last.checkedAt, later);
    });

    test('a server slower than its patience is given up on', () async {
      // One bar of signal: not an error, just no answer yet. The copy stays
      // on screen and the lifter is told it is the copy.
      final remote = _Remote();
      final cache = InMemoryPlanCache();
      await CachedStandingPlanStore(remote: remote, cache: cache).active();

      remote.delay = const Duration(seconds: 1);
      final reads = await CachedStandingPlanStore(
        remote: remote,
        cache: cache,
        patience: const Duration(milliseconds: 20),
      ).watch().toList();

      expect(reads.map((r) => r.freshness), <PlanFreshness>[
        PlanFreshness.saved,
        PlanFreshness.unreachable,
      ]);
      expect(
        reads.last.plan?.slots['Push']!.single.movement,
        'Barbell Bench Press',
      );
    });

    test('with nothing saved, a slow server is waited for', () async {
      // Nothing to show instead, so giving up would only turn a slow answer
      // into no answer.
      final remote = _Remote()..delay = const Duration(milliseconds: 60);
      final reads = await CachedStandingPlanStore(
        remote: remote,
        cache: InMemoryPlanCache(),
        patience: const Duration(milliseconds: 10),
      ).watch().toList();

      expect(reads.single.freshness, PlanFreshness.checked);
      expect(reads.single.plan?.id, 'p');
    });

    test('a slow answer does not undo a plan built while it was out', () async {
      // Asked on the way into the gym; the split changed before the server
      // answered with the old week. The copy keeps the new one.
      final remote = _Remote()..delay = const Duration(milliseconds: 60);
      final cache = InMemoryPlanCache();
      final store = CachedStandingPlanStore(remote: remote, cache: cache);

      final reading = store.watch().toList();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final next = StandingPlan(
        id: 'q',
        name: 'Upper / Lower',
        dayOrder: const <String>['Upper', 'Lower'],
        weekdays: const <int>[2, 4],
        slots: const <String, List<MovementSlot>>{},
      );
      remote.delay = null;
      await store.replace(next);
      remote.live = plan; // the server's slow answer is still the old week

      expect((await reading).last.plan?.id, 'q');
      remote.reachable = false;
      expect((await store.active())?.id, 'q');
    });

    test('nothing saved and no signal is no plan, said as such', () async {
      final reads = await CachedStandingPlanStore(
        remote: _Remote()..reachable = false,
        cache: InMemoryPlanCache(),
      ).watch().toList();

      expect(reads.single.freshness, PlanFreshness.unreachable);
      expect(reads.single.plan, isNull);
      expect(reads.single.checkedAt, isNull);
    });

    test('the copy is shown only to the account it was read for', () async {
      var account = 'u1';
      final remote = _Remote();
      final cache = InMemoryPlanCache();
      final store = CachedStandingPlanStore(
        remote: remote,
        cache: cache,
        account: () => account,
      );
      await store.active();

      account = 'u2';
      remote.reachable = false;
      final reads = await store.watch().toList();
      // u1's week is not on Track for u2, even for the seconds before the
      // server would have said so.
      expect(reads.single.freshness, PlanFreshness.unreachable);
      expect(reads.single.plan, isNull);
      expect(await cache.read(), isNull);
    });

    test('signed out, the copy is not shown and is cleared', () async {
      String? account = 'u1';
      final remote = _Remote();
      final cache = InMemoryPlanCache();
      final store = CachedStandingPlanStore(
        remote: remote,
        cache: cache,
        account: () => account,
      );
      await store.active();

      account = null;
      remote.reachable = false;
      expect(await store.active(), isNull);
      expect(await cache.read(), isNull);
    });

    test(
      'a copy saved by 2.0.0 is no copy, and the server replaces it',
      () async {
        // 2.0.0 saved the bare plan: no owner and no time. It parses, so it is
        // the format number and not a failed parse that turns it away.
        final cache = InMemoryPlanCache(jsonEncode(planToJson(plan)));
        final remote = _Remote()..reachable = false;
        final store = CachedStandingPlanStore(remote: remote, cache: cache);
        expect(await store.active(), isNull);

        remote.reachable = true;
        expect((await store.active())?.id, 'p');
        final saved = jsonDecode((await cache.read())!) as Map<String, Object?>;
        expect(saved['format'], 2);
      },
    );
  });
}
