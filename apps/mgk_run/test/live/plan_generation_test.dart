@Tags(<String>['live'])
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/coach_service.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_service.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'live_backend.dart';

/// **Does the runner actually get a plan the model wrote?**
///
/// A unit test asks whether `PlanService` generates plans correctly. It always
/// did. What no unit test could ask is whether anything *calls* it — and for a
/// year nothing did, so every plan Runio produced was the deterministic
/// fallback wearing the coach's name.
///
/// That is the shape of this whole file: each test states an outcome a runner
/// would notice, against the real backend, so it cannot pass while the feature
/// is disconnected, unreachable, or quietly falling back.
///
/// ```
/// flutter test --tags live --dart-define-from-file=config/app_config.json
/// ```
void main() {
  if (!liveConfigured) {
    test('live plan generation', () {}, skip: liveSkipReason);
    return;
  }

  late SupabaseClient client;
  late PlanService planner;

  setUpAll(() async {
    client = await signedInClient();
    // Running this file is the consent: a live test is a deliberate send.
    // Granted in memory, never written to the dev account's metadata.
    planner = PlanService(
      client: CoachService(
        client: client,
        consent: InMemoryAiConsentStore.granted(),
      ),
    );
  });

  tearDownAll(() async => client.dispose());

  /// The marathon runner: a goal and a date, so a block.
  RunnerProfile block() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime.now().add(const Duration(days: 120)),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  /// A distance to reach with no race entered (ADR-0011).
  RunnerProfile horizon() => const RunnerProfile(
    goalDistanceMeters: 21097,
    currentWeeklyMeters: 25000,
    longestRecentMeters: 12000,
    daysPerWeek: 4,
    availableWeekdays: <int>{2, 4, 6, 7},
  );

  /// The parkrun regular: no goal at all.
  RunnerProfile rhythm() => const RunnerProfile(
    currentWeeklyMeters: 20000,
    longestRecentMeters: 9000,
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

  test('the model is reached, and a sound arc always results', () {
    // Two guarantees, deliberately of different strengths.
    //
    // **The model was reached.** `modelAttempts > 0` is the wiring assertion:
    // the surface exists, the function answered, and generation went through
    // PlanService rather than round the side of it. A year of orphaned code
    // would have failed this.
    //
    // **A sound plan resulted.** Model or fallback, the runner gets an arc the
    // validator accepts. That is the guarantee ADR-0003 actually makes.
    //
    // What is NOT asserted is `source == model`, and that is the interesting
    // part. Writing this test I saw four skeleton attempts across two runs and
    // only one passed the validator: once it took two goes, once both failed
    // and it fell back. So plans land on the deterministic builder a real
    // fraction of the time in production right now.
    //
    // Asserting `model` here would make the test flaky and teach everyone to
    // ignore it. First-attempt validator pass rate is a **model quality
    // measurement**, not a regression invariant — it belongs in the bake-off,
    // where it is the score, and where a model needing two goes every time is
    // correctly ranked as worse than its price suggests.
    return live(() async {
      final result = await planner.generateSkeleton(block());
      if (spentAllowance(result.limit)) return;

      expect(
        result.modelAttempts,
        greaterThan(0),
        reason: 'generation never called the model at all',
      );
      expect(result.plan.weeks, isNotEmpty);
      expect(
        validateSkeleton(
          result.plan,
          block(),
          rules: PlanRules.forShape(shapeOf(block())),
        ).isValid,
        isTrue,
        reason: 'the runner was handed an arc the validator would reject',
      );
    });
  });

  test('a week is reached and comes back sound', () {
    // Same split: attempts prove the wiring, validity is the promise. Weeks
    // passed the validator on both runs where skeletons did not, which is
    // unsurprising — filling one slot is a smaller job than shaping a whole arc
    // with a ramp, a deload cadence and a taper. Worth measuring separately in
    // the bake-off rather than assuming the two track each other.
    return live(() async {
      final skeleton = await planner.generateSkeleton(block());
      if (spentAllowance(skeleton.limit)) return;
      final slot = skeleton.plan.weeks.first;
      final result = await planner.generateWeek(slot, block());
      if (spentAllowance(result.limit)) return;

      expect(result.modelAttempts, greaterThan(0));
      expect(result.plan.runs, isNotEmpty);
      expect(
        validateWeek(
          result.plan,
          slot,
          block(),
          rules: PlanRules.forShape(shapeOf(block())),
        ).isValid,
        isTrue,
      );
    });
  });

  test('a horizon runner gets a plan', () {
    // A distance with no date. Force-unwrapping that date crashed this path
    // twice, in two different screens, and both times every test had built a
    // block.
    return live(() async {
      final result = await planner.generateSkeleton(horizon());
      if (spentAllowance(result.limit)) return;
      expect(result.plan.weeks, isNotEmpty);
    });
  });

  test('a rhythm runner gets a plan', () {
    // No goal at all. The shape ADR-0011 exists for, and the one most likely to
    // be broken by code written while picturing a marathon.
    return live(() async {
      final result = await planner.generateSkeleton(rhythm());
      if (spentAllowance(result.limit)) return;
      expect(result.plan.weeks, isNotEmpty);
    });
  });

  test('creating a plan puts this week on the device, end to end', () {
    // The whole path a runner takes: tap "Build my plan", get a plan, and have
    // this week's sessions on disk. Through PlanRepository, which is what the
    // shell actually calls — so this is the test that would fail if the
    // generator were ever unwired from the app again.
    return live(() async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final plans = PlanRepository(
        store: DriftPlanStore(db),
        generator: planner,
        newId: () => 'live-plan',
      );
      final plan = await plans.create(block());

      expect(plan.skeleton.weeks, isNotEmpty);
      final week = await DriftPlanStore(
        db,
      ).loadWeek(plan, plan.weekIndexOn(DateTime.now()));
      expect(
        week,
        isNotNull,
        reason: 'create materialises the current week, so today has a session',
      );
      expect(week!.runs, isNotEmpty);
    });
  });
}
