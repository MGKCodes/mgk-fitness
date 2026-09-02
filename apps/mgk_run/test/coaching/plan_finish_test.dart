import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_history.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/race_day.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// **Something writes `completed`.** For a year `plans.status` documented four
/// values and the app produced two of them, so a sixteen-week block ended by
/// being quietly superseded the next time anybody built a plan (ADR-0027).
///
/// These tests are about what reaches disk and what comes back off it: the two
/// endings, the result the runner confirmed, and the runner who never raced and
/// so never taps anything at all.
void main() {
  late AppDatabase db;

  final created = DateTime(2026, 3, 2); // a Monday
  final raceDay = DateTime(2026, 5, 24);

  RunnerProfile blockProfile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: raceDay,
    currentWeeklyMeters: 40000,
    longestRecentMeters: 22000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  RunnerProfile rhythmProfile() => const RunnerProfile(
    currentWeeklyMeters: 20000,
    longestRecentMeters: 8000,
    daysPerWeek: 3,
    availableWeekdays: <int>{2, 4, 6},
    commitments: <PlanCommitment>[
      PlanCommitment(
        weekday: DateTime.saturday,
        distanceMeters: 5000,
        label: 'parkrun',
        timed: true,
      ),
    ],
  );

  StoredPlan planFor(RunnerProfile profile, {String id = 'plan-1'}) =>
      StoredPlan(
        id: id,
        profile: profile,
        skeleton: buildSkeleton(profile, now: created),
        startDate: mondayOf(created),
      );

  RunSummary theRace() => RunSummary(
    id: 'race',
    startedAt: DateTime(2026, 5, 24, 9),
    duration: const Duration(hours: 3, minutes: 42, seconds: 18),
    distanceMeters: 42610,
  );

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('closing a plan out', () {
    test('a race writes completed, the time, and when', () async {
      final store = DriftPlanStore(db);
      final plan = planFor(blockProfile());
      await store.savePlan(plan);

      await store.closePlan(
        plan,
        closure: PlanClosure.raced,
        raceTime: const Duration(hours: 3, minutes: 41, seconds: 30),
      );

      final row = (await db.select(db.plans).get()).single;
      expect(row.status, planStatusCompleted);
      expect(row.raceTimeS, 13290);
      expect(row.finishedAt, isNotNull);

      // And it is no longer the plan the runner is on.
      expect(await store.loadActivePlan(), isNull);
    });

    test('not racing writes abandoned, and never a time', () async {
      final store = DriftPlanStore(db);
      final plan = planFor(blockProfile());
      await store.savePlan(plan);

      await store.closePlan(
        plan,
        closure: PlanClosure.didNotRace,
        // Passed on purpose: a time for a race that did not happen must not
        // reach disk however it is handed in.
        raceTime: const Duration(hours: 3),
      );

      final row = (await db.select(db.plans).get()).single;
      expect(row.status, planStatusAbandoned);
      expect(row.raceTimeS, isNull);
    });

    test('the plan is still a record of what they committed to', () async {
      final store = DriftPlanStore(db);
      final plan = planFor(blockProfile());
      await store.savePlan(plan);
      await store.closePlan(plan, closure: PlanClosure.didNotRace);

      // The arc survives, because a plan is not deleted when it ends — the
      // same rule superseding has always followed.
      expect(await db.weeksForPlan(plan.id), isNotEmpty);
    });

    test('closing a plan this device does not have is refused', () async {
      final store = DriftPlanStore(db);
      expect(
        () => store.closePlan(
          planFor(blockProfile(), id: 'never-stored'),
          closure: PlanClosure.raced,
        ),
        throwsA(isA<PlanStoreException>()),
      );
    });
  });

  group('what history says afterwards', () {
    test('a finished block reads as raced, with its time', () async {
      final store = DriftPlanStore(db);
      final plan = planFor(blockProfile());
      await store.savePlan(plan);
      await store.closePlan(
        plan,
        closure: PlanClosure.raced,
        raceTime: const Duration(hours: 3, minutes: 42, seconds: 18),
      );

      final record = (await store.loadHistory()).single;
      expect(record.isActive, isFalse);
      expect(record.outcome, PlanOutcome.raced);
      expect(
        record.raceTime,
        const Duration(hours: 3, minutes: 42, seconds: 18),
      );
      expect(record.finishedAt, isNotNull);
    });

    test(
      'a block they did not start is its own outcome, not "left early"',
      () async {
        final store = DriftPlanStore(db);
        final plan = planFor(blockProfile());
        await store.savePlan(plan);
        await store.closePlan(plan, closure: PlanClosure.didNotRace);

        expect(
          (await store.loadHistory()).single.outcome,
          PlanOutcome.didNotRace,
        );
      },
    );

    test(
      'a plan stored before any of this still reads as it always did',
      () async {
        // No closure recorded, superseded by the next plan: the inference from
        // the dates is all there is, and it has to keep working. The race is
        // dated well ahead of the supersede so the inference has something to
        // conclude — they left this block before it got anywhere near the day.
        final store = DriftPlanStore(db);
        final aimedAtNextYear = RunnerProfile(
          goalDistanceMeters: 42195,
          eventDate: DateTime.now().add(const Duration(days: 200)),
          currentWeeklyMeters: 40000,
          longestRecentMeters: 22000,
          daysPerWeek: 5,
          availableWeekdays: const <int>{1, 2, 4, 6, 7},
        );
        await store.savePlan(planFor(aimedAtNextYear, id: 'plan-old'));
        await store.savePlan(planFor(aimedAtNextYear, id: 'plan-new'));

        final history = await store.loadHistory();
        expect(history.first.closure, isNull);
        expect(history.first.raceTime, isNull);
        expect(history.first.outcome, PlanOutcome.leftEarly);
      },
    );

    test('the coach is told what they ran', () async {
      final store = DriftPlanStore(db);
      final plan = planFor(blockProfile());
      await store.savePlan(plan);
      await store.closePlan(
        plan,
        closure: PlanClosure.raced,
        raceTime: const Duration(hours: 3, minutes: 42, seconds: 18),
      );

      final line = planHistoryLine(
        labelPlans(await store.loadHistory()),
        distance: (m) => '${(m / 1000).round()} km',
      );
      expect(line, contains('3:42:18'));
    });
  });

  group('the runner who never races', () {
    test('is closed from the log once the grace period is up', () async {
      final store = DriftPlanStore(db);
      final plan = planFor(blockProfile());
      await store.savePlan(plan);

      final plans = PlanRepository(
        store: store,
        now: () => raceDay.add(const Duration(days: kRaceGraceDays + 1)),
      );

      expect(
        await plans.closeIfOverdue(plan, const <RunSummary>[]),
        PlanClosure.didNotRace,
      );
      expect(await store.loadActivePlan(), isNull);
      expect(
        (await db.select(db.plans).get()).single.status,
        planStatusAbandoned,
      );
    });

    test(
      'and a runner who raced but never said so is closed as raced',
      () async {
        final store = DriftPlanStore(db);
        final plan = planFor(blockProfile());
        await store.savePlan(plan);

        final plans = PlanRepository(
          store: store,
          now: () => raceDay.add(const Duration(days: kRaceGraceDays + 1)),
        );

        expect(
          await plans.closeIfOverdue(plan, <RunSummary>[theRace()]),
          PlanClosure.raced,
        );
        final row = (await db.select(db.plans).get()).single;
        expect(row.status, planStatusCompleted);
        // Read off the run, which is the same evidence the sheet would have
        // shown them before they confirmed.
        expect(
          row.raceTimeS,
          const Duration(hours: 3, minutes: 42, seconds: 18).inSeconds,
        );
      },
    );

    test(
      'nothing is closed while the runner still has time to answer',
      () async {
        final store = DriftPlanStore(db);
        final plan = planFor(blockProfile());
        await store.savePlan(plan);

        final plans = PlanRepository(
          store: store,
          now: () => raceDay.add(const Duration(days: 1)),
        );

        expect(await plans.closeIfOverdue(plan, const <RunSummary>[]), isNull);
        expect(await store.loadActivePlan(), isNotNull);
      },
    );

    test('a rhythm is never closed, however long it runs', () async {
      final store = DriftPlanStore(db);
      final plan = planFor(rhythmProfile());
      await store.savePlan(plan);

      final plans = PlanRepository(
        store: store,
        now: () => DateTime(2030, 1, 1),
      );

      expect(await plans.closeIfOverdue(plan, const <RunSummary>[]), isNull);
      expect(await store.loadActivePlan(), isNotNull);
    });
  });

  group('the in-memory store behaves the same way', () {
    test('closing moves the plan into history with its result', () async {
      final store = InMemoryPlanStore(now: () => DateTime(2026, 5, 25));
      final plan = planFor(blockProfile());
      await store.savePlan(plan);
      await store.closePlan(
        plan,
        closure: PlanClosure.raced,
        raceTime: const Duration(hours: 3, minutes: 42, seconds: 18),
      );

      expect(await store.loadActivePlan(), isNull);
      final record = (await store.loadHistory()).single;
      expect(record.outcome, PlanOutcome.raced);
      expect(
        record.raceTime,
        const Duration(hours: 3, minutes: 42, seconds: 18),
      );
    });

    test('and drops a time for a race that did not happen', () async {
      final store = InMemoryPlanStore(now: () => DateTime(2026, 5, 25));
      final plan = planFor(blockProfile());
      await store.savePlan(plan);
      await store.closePlan(
        plan,
        closure: PlanClosure.didNotRace,
        raceTime: const Duration(hours: 3),
      );

      expect((await store.loadHistory()).single.raceTime, isNull);
    });
  });
}
