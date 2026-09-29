// Regression for EDGE-17: weeks 3+ of a plan are written a week ahead by
// PlanRepository.lookAhead, called from HomeShell's refresh. That path built
// the model's request with no raceWeekday and validated its answer with no
// weekStart/now, so a session on race day — the one thing
// plan_validator.dart's session_on_race_day rule exists to catch — passed
// straight through: the model was never told which day to avoid and the
// validator was never told which day was the race. See the throwaway
// reproduction under
// .claude/worktrees/review-edge/apps/mgk_run/test/zz_edge_review/lookahead_race_day_test.dart.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_service.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

/// Answers the way a model that has not learned to dodge race day would: the
/// builder's own shape, long run on the latest available day, ignoring
/// [raceWeekday] entirely. Records what it was told so the test can check
/// the wiring, not just the outcome.
class _ModelThatIgnoresRaceDay implements PlanClient {
  final List<int?> raceWeekdaysSeen = <int?>[];

  @override
  Future<PlanSkeleton?> proposeSkeleton({
    required RunnerProfile profile,
    List<String> violations = const <String>[],
  }) async => null;

  @override
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations = const <String>[],
    int? raceWeekday,
  }) async {
    raceWeekdaysSeen.add(raceWeekday);
    return buildFallbackWeek(slot, profile); // no exclusions — the old bug
  }

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async => null;
}

void main() {
  test(
    'lookAhead keeps the model off race day, and the validator off its blind '
    'spot, for a race week written weeks 3+',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final race = DateTime(2026, 11, 15); // a Sunday
      var clock = DateTime(2026, 9, 29, 9); // Tuesday; plan starts Mon 5 Oct
      final model = _ModelThatIgnoresRaceDay();
      final repo = PlanRepository(
        store: DriftPlanStore(db),
        generator: PlanService(client: model, now: () => clock),
        now: () => clock,
      );
      final plan = await repo.create(
        RunnerProfile(
          goalDistanceMeters: 21097.5,
          eventDate: race,
          currentWeeklyMeters: 30000,
          longestRecentMeters: 14000,
          daysPerWeek: 5,
          availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
        ),
      );
      final raceWeek = plan.weekIndexOn(race);
      // The week before race week, when HomeShell's refresh calls lookAhead
      // — the exact moment the throwaway reproduction caught this in.
      clock = plan
          .dateFor(weekIndex: raceWeek - 1, weekday: 2)
          .add(const Duration(hours: 9));

      final wrote = await repo.lookAhead(plan);

      // The model was told which day to avoid...
      expect(model.raceWeekdaysSeen, isNotEmpty);
      expect(model.raceWeekdaysSeen.last, race.weekday);
      // ...ignored it anyway (the fake's whole point). Before this fix the
      // validator had no calendar either, so a session on race day passed
      // as a valid proposal and lookAhead stored it — the throwaway
      // reproduction's own finding. Now the validator catches it
      // (session_on_race_day), the model's two attempts both fail, and
      // lookAhead's own rule — "only a week the model actually produced is
      // written" — means the deterministic fallback that follows is
      // correctly *not* stored either: nothing reaches disk for the runner
      // to train off, rather than a plan-shaped object with a run on the
      // event itself.
      expect(
        wrote,
        isFalse,
        reason: 'a week with a session on race day must never be written',
      );
      expect(
        await DriftPlanStore(db).loadWeek(plan, raceWeek),
        isNull,
        reason:
            'the slot stays open, for weekFor (which does exclude race '
            'day from its own fallback) to fill properly on next read',
      );

      await db.close();
    },
  );
}
