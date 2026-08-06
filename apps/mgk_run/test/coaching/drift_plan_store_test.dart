import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';

/// The plan must survive an app restart. These tests treat "a fresh
/// [DriftPlanStore] over the same database" as a relaunch — the widget tree and
/// every in-memory object are gone, only the rows remain.
void main() {
  late AppDatabase db;

  final DateTime created = DateTime(2026, 7, 26); // a Sunday
  final DateTime monday = mondayOf(created); // 2026-07-20

  RunnerProfile aProfile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 15),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
    injuryNotes: 'left achilles, watch the volume',
  );

  StoredPlan aPlan({String id = 'plan-1', RunnerProfile? profile}) {
    final p = profile ?? aProfile();
    return StoredPlan(
      id: id,
      profile: p,
      skeleton: buildSkeleton(p, now: created),
      startDate: monday,
    );
  }

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('round trip', () {
    test('a saved plan reloads identically after a restart', () async {
      final plan = aPlan();
      await DriftPlanStore(db).savePlan(plan);

      // A brand-new store, as a relaunch would build.
      final reloaded = await DriftPlanStore(db).loadActivePlan();

      expect(reloaded, isNotNull);
      expect(reloaded!.id, plan.id);
      expect(reloaded.startDate, monday);

      final p = reloaded.profile;
      final original = plan.profile;
      expect(p.goalDistanceMeters, original.goalDistanceMeters);
      expect(p.eventDate, original.eventDate);
      expect(p.currentWeeklyMeters, original.currentWeeklyMeters);
      expect(p.longestRecentMeters, original.longestRecentMeters);
      expect(p.daysPerWeek, original.daysPerWeek);
      expect(p.availableWeekdays, original.availableWeekdays);
      expect(p.timeTrialDistanceMeters, original.timeTrialDistanceMeters);
      expect(p.timeTrialDuration, original.timeTrialDuration);
      expect(p.injuryNotes, original.injuryNotes);

      expect(reloaded.skeleton.weeks, hasLength(plan.skeleton.weeks.length));
      for (var i = 0; i < plan.skeleton.weeks.length; i++) {
        final was = plan.skeleton.weeks[i];
        final now = reloaded.skeleton.weeks[i];
        expect(now.index, was.index);
        expect(now.phase, was.phase);
        expect(now.isDeload, was.isDeload);
        expect(now.volumeMeters, closeTo(was.volumeMeters, 0.01));
        expect(now.longRunMeters, closeTo(was.longRunMeters, 0.01));
      }
    });

    test(
      'a nullable-free profile round trips (no time trial, no notes)',
      () async {
        final bare = RunnerProfile(
          goalDistanceMeters: 10000,
          eventDate: DateTime(2026, 10, 1),
          currentWeeklyMeters: 20000,
          longestRecentMeters: 8000,
          daysPerWeek: 3,
          availableWeekdays: const <int>{2, 4, 6},
        );
        await DriftPlanStore(db).savePlan(aPlan(profile: bare));

        final reloaded = await DriftPlanStore(db).loadActivePlan();
        expect(reloaded!.profile.timeTrialDistanceMeters, isNull);
        expect(reloaded.profile.timeTrialDuration, isNull);
        expect(reloaded.profile.injuryNotes, isNull);
        expect(reloaded.profile.availableWeekdays, const <int>{2, 4, 6});
      },
    );

    test(
      'a week of sessions round trips, rest days staying rest days',
      () async {
        final store = DriftPlanStore(db);
        final plan = aPlan();
        await store.savePlan(plan);

        final slot = plan.skeleton.weeks[3];
        final week = buildFallbackWeek(slot, plan.profile);
        await store.saveWeek(plan, week);

        final reloaded = await DriftPlanStore(db).loadWeek(plan, slot.index);
        expect(reloaded, isNotNull);
        expect(reloaded!.skeletonIndex, slot.index);
        expect(reloaded.provisional, week.provisional);
        expect(
          reloaded.runs.map((s) => s.weekday),
          week.runs.map((s) => s.weekday),
        );
        expect(reloaded.runs.map((s) => s.kind), week.runs.map((s) => s.kind));
        expect(reloaded.volumeMeters, closeTo(week.volumeMeters, 0.01));

        // Days the runner is not training on have no session at all.
        for (var day = 1; day <= 7; day++) {
          final had = week.runOn(day);
          expect(
            reloaded.runOn(day) == null,
            had == null,
            reason: 'weekday $day',
          );
        }
      },
    );

    test('an ungenerated week reads as null, not as an empty week', () async {
      final store = DriftPlanStore(db);
      final plan = aPlan();
      await store.savePlan(plan);
      expect(await store.loadWeek(plan, 9), isNull);
    });
  });

  group('validator invariants survive persistence', () {
    // The load-bearing regression: a plan that validated when generated must
    // still validate after a save/reload. A lossy round trip (a dropped deload,
    // a truncated volume) would silently corrupt a runner's block.
    test('a reloaded skeleton still passes validateSkeleton', () async {
      final plan = aPlan();
      expect(
        validateSkeleton(plan.skeleton, plan.profile).isValid,
        isTrue,
        reason: 'precondition: the generated skeleton is valid',
      );

      await DriftPlanStore(db).savePlan(plan);
      final reloaded = await DriftPlanStore(db).loadActivePlan();

      final result = validateSkeleton(reloaded!.skeleton, reloaded.profile);
      expect(
        result.isValid,
        isTrue,
        reason: 'violations after reload: ${result.violations}',
      );
    });

    test(
      'a reloaded week still passes validateWeek against its slot',
      () async {
        final store = DriftPlanStore(db);
        final plan = aPlan();
        await store.savePlan(plan);

        // Every week of the plan, not just a convenient one.
        for (final slot in plan.skeleton.weeks) {
          final week = buildFallbackWeek(slot, plan.profile);
          await store.saveWeek(plan, week);
          final reloaded = await DriftPlanStore(db).loadWeek(plan, slot.index);
          final result = validateWeek(reloaded!, slot, plan.profile);
          expect(
            result.isValid,
            isTrue,
            reason: 'week ${slot.index} violations: ${result.violations}',
          );
        }
      },
    );

    test('the profile reloads with the plan, so it cannot drift out from '
        'under the skeleton', () async {
      // The plan snapshots its profile. Storing a *different* current profile
      // must not change how the stored plan validates.
      final plan = aPlan();
      await DriftPlanStore(db).savePlan(plan);

      final reloaded = await DriftPlanStore(db).loadActivePlan();
      expect(reloaded!.profile.currentWeeklyMeters, 40000);
      expect(
        validateSkeleton(reloaded.skeleton, reloaded.profile).isValid,
        isTrue,
      );
    });
  });

  group('session status durability', () {
    test('a mark is on disk immediately and survives a restart', () async {
      final store = DriftPlanStore(db);
      final plan = aPlan();
      await store.savePlan(plan);

      final slot = plan.skeleton.weeks.first;
      final week = buildFallbackWeek(slot, plan.profile);
      await store.saveWeek(plan, week);

      final trainingDay = week.runs.first.weekday;
      final date = plan.dateFor(weekIndex: slot.index, weekday: trainingDay);

      expect(await store.statusOn(plan, date), SessionStatus.planned);
      expect(
        await store.setStatusOn(plan, date, SessionStatus.completed),
        isTrue,
      );

      // A relaunch: nothing in memory, only rows.
      expect(
        await DriftPlanStore(db).statusOn(plan, date),
        SessionStatus.completed,
      );
    });

    test('skipping and undoing are equally durable', () async {
      final store = DriftPlanStore(db);
      final plan = aPlan();
      await store.savePlan(plan);
      final slot = plan.skeleton.weeks.first;
      final week = buildFallbackWeek(slot, plan.profile);
      await store.saveWeek(plan, week);
      final date = plan.dateFor(
        weekIndex: slot.index,
        weekday: week.runs.first.weekday,
      );

      await store.setStatusOn(plan, date, SessionStatus.skipped);
      expect(
        await DriftPlanStore(db).statusOn(plan, date),
        SessionStatus.skipped,
      );

      await store.setStatusOn(plan, date, SessionStatus.planned);
      expect(
        await DriftPlanStore(db).statusOn(plan, date),
        SessionStatus.planned,
      );
    });

    test('a rest day has no status and cannot be marked', () async {
      final store = DriftPlanStore(db);
      final plan = aPlan();
      await store.savePlan(plan);
      final slot = plan.skeleton.weeks.first;
      final week = buildFallbackWeek(slot, plan.profile);
      await store.saveWeek(plan, week);

      final restDay = <int>[
        for (var d = 1; d <= 7; d++)
          if (week.runOn(d) == null) d,
      ].first;
      final date = plan.dateFor(weekIndex: slot.index, weekday: restDay);

      expect(await store.statusOn(plan, date), isNull);
      // Returning false is the contract: a caller must not read a no-op as a
      // durable write.
      expect(
        await store.setStatusOn(plan, date, SessionStatus.completed),
        isFalse,
      );
    });

    test('rewriting a week keeps statuses the runner already set', () async {
      final store = DriftPlanStore(db);
      final plan = aPlan();
      await store.savePlan(plan);
      final slot = plan.skeleton.weeks.first;
      final week = buildFallbackWeek(slot, plan.profile);
      await store.saveWeek(plan, week);

      final day = week.runs.first.weekday;
      final date = plan.dateFor(weekIndex: slot.index, weekday: day);
      await store.setStatusOn(plan, date, SessionStatus.completed);

      // An adaptation rewrites the week's shape, keeping that day.
      await store.saveWeek(plan, week);

      expect(await store.statusOn(plan, date), SessionStatus.completed);
    });

    test(
      'a status is scoped to its date, not smeared across the week',
      () async {
        final store = DriftPlanStore(db);
        final plan = aPlan();
        await store.savePlan(plan);
        final slot = plan.skeleton.weeks.first;
        final week = buildFallbackWeek(slot, plan.profile);
        await store.saveWeek(plan, week);

        final days = week.runs.map((s) => s.weekday).toList();
        final first = plan.dateFor(weekIndex: slot.index, weekday: days.first);
        final second = plan.dateFor(weekIndex: slot.index, weekday: days[1]);

        await store.setStatusOn(plan, first, SessionStatus.completed);

        expect(await store.statusOn(plan, first), SessionStatus.completed);
        expect(await store.statusOn(plan, second), SessionStatus.planned);
      },
    );

    /// A rhythm re-uses one skeleton week every cycle, so the `scheduled_date`
    /// written when the week was first materialised is only ever *one* of the
    /// weeks it stands for. Looking a session up by that date found nothing
    /// from the second cycle onward: a parkrun runner's "Mark done" returned
    /// false and silently did nothing, every week, forever.
    test(
      'a rhythm can be marked in a later cycle, not just the first',
      () async {
        final store = DriftPlanStore(db);
        final parkrunner = const RunnerProfile(
          currentWeeklyMeters: 5000,
          longestRecentMeters: 5000,
          daysPerWeek: 1,
          availableWeekdays: <int>{DateTime.saturday},
          commitments: <PlanCommitment>[
            PlanCommitment(
              weekday: DateTime.saturday,
              distanceMeters: 5000,
              label: 'parkrun',
            ),
          ],
        );
        final plan = aPlan(id: 'rhythm-1', profile: parkrunner);
        await store.savePlan(plan);

        final slot = plan.skeleton.weeks.first;
        final week = buildFallbackWeek(slot, plan.profile);
        await store.saveWeek(plan, week);

        final day = week.runs.first.weekday;

        // Three full cycles on: the same slot comes round again, so the row is
        // still the right one — but the calendar date has moved months past the
        // `scheduled_date` stored with it.
        final cycles = plan.skeleton.weeks.length * 3;
        final later = addDays(plan.startDate, cycles * 7 + (day - 1));

        expect(
          plan.weekIndexOn(later),
          slot.index,
          reason: 'precondition: a whole number of cycles returns to this slot',
        );
        expect(
          plan.dateFor(weekIndex: slot.index, weekday: day),
          isNot(later),
          reason:
              'precondition: the stored scheduled_date is a different week, '
              'which is what a date-keyed lookup used to miss',
        );

        expect(
          await store.setStatusOn(plan, later, SessionStatus.completed),
          isTrue,
          reason: 'marking a run done must not depend on which cycle it is',
        );
        expect(await store.statusOn(plan, later), SessionStatus.completed);
      },
    );
  });

  group('a second plan', () {
    test('supersedes the first without deleting it', () async {
      final store = DriftPlanStore(db);
      await store.savePlan(aPlan(id: 'plan-old'));
      await store.savePlan(aPlan(id: 'plan-new'));

      final active = await store.loadActivePlan();
      expect(active!.id, 'plan-new');

      // The old plan is still a record of what the runner committed to.
      final all = await db.select(db.plans).get();
      expect(
        all.map((p) => p.id),
        containsAll(<String>['plan-old', 'plan-new']),
      );
      expect(
        all.firstWhere((p) => p.id == 'plan-old').status,
        planStatusSuperseded,
      );
      expect(
        all.firstWhere((p) => p.id == 'plan-new').status,
        planStatusActive,
      );
    });

    test('does not inherit the old plan\'s weeks or marks', () async {
      final store = DriftPlanStore(db);
      final old = aPlan(id: 'plan-old');
      await store.savePlan(old);
      await store.saveWeek(
        old,
        buildFallbackWeek(old.skeleton.weeks.first, old.profile),
      );

      final fresh = aPlan(id: 'plan-new');
      await store.savePlan(fresh);

      expect(await store.loadWeek(fresh, 1), isNull);
    });
  });

  group('strict decoding', () {
    test('an unknown phase raises rather than dropping the week', () async {
      final store = DriftPlanStore(db);
      final plan = aPlan();
      await store.savePlan(plan);

      // Simulate a row written by a newer/incompatible build.
      await (db.update(db.planWeeks)
            ..where((w) => w.planId.equals(plan.id) & w.weekNumber.equals(2)))
          .write(const PlanWeeksCompanion(phase: Value('supercompensation')));

      await expectLater(
        DriftPlanStore(db).loadActivePlan(),
        throwsA(isA<PlanStoreException>()),
      );
    });

    test(
      'an unknown session kind raises rather than dropping the day',
      () async {
        final store = DriftPlanStore(db);
        final plan = aPlan();
        await store.savePlan(plan);
        final slot = plan.skeleton.weeks.first;
        await store.saveWeek(plan, buildFallbackWeek(slot, plan.profile));

        await (db.update(db.planSessions)
              ..where((s) => s.planId.equals(plan.id)))
            .write(const PlanSessionsCompanion(kind: Value('fartlek-ish')));

        await expectLater(
          DriftPlanStore(db).loadWeek(plan, slot.index),
          throwsA(isA<PlanStoreException>()),
        );
      },
    );

    test('a plan with no skeleton weeks raises rather than showing an '
        'arc-less plan', () async {
      final store = DriftPlanStore(db);
      final plan = aPlan();
      await store.savePlan(plan);
      await (db.delete(
        db.planWeeks,
      )..where((w) => w.planId.equals(plan.id))).go();

      await expectLater(
        DriftPlanStore(db).loadActivePlan(),
        throwsA(isA<PlanStoreException>()),
      );
    });

    test('an unreadable weekday list raises', () async {
      final store = DriftPlanStore(db);
      final plan = aPlan();
      await store.savePlan(plan);
      await (db.update(db.plans)..where((p) => p.id.equals(plan.id))).write(
        const PlansCompanion(availableWeekdays: Value('mon,tue')),
      );

      await expectLater(
        DriftPlanStore(db).loadActivePlan(),
        throwsA(isA<PlanStoreException>()),
      );
    });
  });

  group('local schema migration', () {
    test('the plan tables are additive — an existing run is untouched', () async {
      // Runs and plans share the database; adding plan storage must not disturb
      // recording, which is the offline-first path that matters most.
      await db.upsertRun(
        RunsCompanion.insert(
          id: 'run-1',
          startedAt: DateTime.utc(2026, 7, 20, 7),
          durationS: 1800,
          distanceM: 5000,
          source: 'gps',
          type: 'outdoor',
        ),
      );
      await DriftPlanStore(db).savePlan(aPlan());

      final runs = await db.allRuns();
      expect(runs, hasLength(1));
      expect(runs.single.distanceM, 5000);
    });
  });
}
