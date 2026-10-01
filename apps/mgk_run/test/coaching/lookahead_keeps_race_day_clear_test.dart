// Regression for EDGE-17: weeks 3+ of a plan are written a week ahead by
// PlanRepository.lookAhead, called from HomeShell's refresh. That path built
// the model's request with no raceWeekday and validated its answer with no
// weekStart/now, so a session on race day — the one thing
// plan_validator.dart's session_on_race_day rule exists to catch — passed
// straight through: the model was never told which day to avoid and the
// validator was never told which day was the race. See the throwaway
// reproduction under
// .claude/worktrees/review-edge/apps/mgk_run/test/zz_edge_review/lookahead_race_day_test.dart.
//
// **How it holds now is different, and stronger** (ADR-0044). The first fix
// told the model which day to avoid and let the validator refuse it when it
// did not listen, which left the slot empty for a later read to fill. Race
// week is no longer proposed at all: PlanService answers from a rule, the
// model is never asked, and lookAhead keeps what comes back.
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
/// builder's own shape, long run on the latest available day. Counts what it
/// was asked for, so the test can show race week never reached it.
class _ModelThatIgnoresRaceDay implements PlanClient {
  int weeksAsked = 0;

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
    weeksAsked++;
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
  test('lookAhead writes a race week with race day clear, without asking the '
      'model for it', () async {
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

    final asked = model.weeksAsked;
    final wrote = await repo.lookAhead(plan);

    // The model that would have put the long run on the race was not asked.
    expect(model.weeksAsked, asked);
    expect(wrote, isTrue, reason: 'a week built by rule is kept');
    final stored = await DriftPlanStore(db).loadWeek(plan, raceWeek);
    expect(stored, isNotNull);
    expect(
      stored!.sessionOn(race.weekday),
      isNull,
      reason: 'a week with a session on race day must never be written',
    );
    expect(stored.sessions.any((s) => s.kind == SessionKind.long), isFalse);

    await db.close();
  });
}
