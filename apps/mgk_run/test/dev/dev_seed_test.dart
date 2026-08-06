import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/dev/dev_persona.dart';
import 'package:mgk_run/src/dev/dev_seed.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';

/// A fixed Wednesday, so a persona's week numbers do not depend on the day the
/// suite happens to run on.
final DateTime _now = DateTime(2026, 7, 29, 10);

void main() {
  group('every persona', () {
    test('builds — the validator accepts all four', () async {
      // The regression this guards: a fixture the validator would reject is a
      // plan the app could never have produced, and reviewing screens against
      // one means reviewing a state that cannot happen. PlanRepository.create
      // throws PlanStoreException on an invalid skeleton, so building is the
      // assertion.
      for (final persona in DevPersona.values) {
        final seed = await buildDevSeed(persona, now: _now);
        expect(seed.persona, persona, reason: '${persona.name} seeds itself');
      }
    });

    test('no run is dated in the future', () async {
      for (final persona in DevPersona.values) {
        final seed = await buildDevSeed(persona, now: _now);
        for (final run in seed.runs) {
          expect(
            run.startedAt.isAfter(_now),
            isFalse,
            reason: '${persona.name} has a run after "now"',
          );
        }
      }
    });

    test('pace agrees with duration over distance', () async {
      // A log whose pace does not match its own arithmetic makes correct code
      // look broken — the standing card derives pace back out of the two.
      for (final persona in DevPersona.values) {
        final seed = await buildDevSeed(persona, now: _now);
        for (final run in seed.runs) {
          final derived = run.duration.inSeconds / (run.distanceMeters / 1000);
          expect(
            run.avgPaceSecondsPerKm,
            closeTo(derived, 1.0),
            reason: '${persona.name} has a run whose pace is invented',
          );
        }
      }
    });

    test('the log is newest first', () async {
      for (final persona in DevPersona.values) {
        final seed = await buildDevSeed(persona, now: _now);
        for (var i = 1; i < seed.runs.length; i++) {
          expect(
            seed.runs[i - 1].startedAt.isBefore(seed.runs[i].startedAt),
            isFalse,
            reason: '${persona.name} log is out of order at $i',
          );
        }
      }
    });
  });

  group('fresh', () {
    test('has no plan and nothing recorded', () async {
      final seed = await buildDevSeed(DevPersona.fresh, now: _now);
      expect(await seed.planStore.loadActivePlan(), isNull);
      expect(seed.runs, isEmpty);
      expect(await seed.memoryStore.loadSummary(), isNull);
    });
  });

  group('midBlock', () {
    test('is week 4 of a 16-week block', () async {
      final seed = await buildDevSeed(DevPersona.midBlock, now: _now);
      final plan = await seed.planStore.loadActivePlan();
      expect(plan, isNotNull);
      expect(plan!.skeleton.weeks, hasLength(16));
      expect(plan.weekIndexOn(_now), 4);
      expect(shapeOf(plan.profile), PlanShape.block);
      expect(plan.hasEndedBy(_now), isFalse);
    });

    test('has three weeks of running behind it', () async {
      final seed = await buildDevSeed(DevPersona.midBlock, now: _now);
      final plan = (await seed.planStore.loadActivePlan())!;
      expect(seed.runs, isNotEmpty);
      // Nothing before the block started — this runner began three weeks ago.
      final earliest = seed.runs.last.startedAt;
      expect(earliest.isBefore(plan.startDate), isFalse);
    });
  });

  group('secondBlock', () {
    test('is a new block on an old log', () async {
      final seed = await buildDevSeed(DevPersona.secondBlock, now: _now);
      final plan = (await seed.planStore.loadActivePlan())!;
      expect(plan.weekIndexOn(_now), 2, reason: 'the block is a week old');
      expect(plan.skeleton.weeks, hasLength(12));

      // The point of this persona: the log plainly predates the plan. Without
      // that it is indistinguishable from a runner on their first block.
      final earliest = seed.runs.last.startedAt;
      expect(
        earliest.isBefore(plan.startDate.subtract(const Duration(days: 100))),
        isTrue,
        reason: 'the season behind the block is missing',
      );
    });
  });

  group('rhythm', () {
    test('never ends and holds one session a week', () async {
      final seed = await buildDevSeed(DevPersona.rhythm, now: _now);
      final plan = (await seed.planStore.loadActivePlan())!;
      expect(shapeOf(plan.profile), PlanShape.rhythm);
      // A habit is not a project: it must not expire, however long it runs.
      expect(plan.hasEndedBy(_now), isFalse);
      expect(plan.profile.eventDate, isNull);
      expect(plan.profile.goalDistanceMeters, isNull);

      final week = await PlanRepository(
        store: seed.planStore,
      ).weekFor(plan, plan.weekOn(_now));
      expect(week.runs, hasLength(1), reason: 'one run a week, no more');
      expect(week.runs.single.weekday, DateTime.saturday);
    });

    test('turned up every week for twenty weeks', () async {
      final seed = await buildDevSeed(DevPersona.rhythm, now: _now);
      expect(seed.runs.length, greaterThanOrEqualTo(19));
      expect(
        seed.runs.every((r) => r.startedAt.weekday == DateTime.saturday),
        isTrue,
      );
    });
  });

  group('setDevPersona', () {
    tearDown(() => setDevPersona(null));

    test('sets and clears the active persona', () {
      expect(devPersona.value, isNull);
      setDevPersona(DevPersona.rhythm);
      expect(devPersona.value, DevPersona.rhythm);
      setDevPersona(null);
      expect(devPersona.value, isNull);
    });
  });
}
