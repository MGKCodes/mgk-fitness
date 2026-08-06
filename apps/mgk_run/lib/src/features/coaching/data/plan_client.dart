import '../domain/runner_profile.dart';
import '../domain/training_plan.dart';

/// The plan-generation seam — the model's proposal side. The real
/// implementation ([CoachService]) calls the `skeleton` / `week` Edge Function
/// surfaces; a fake drives the orchestrator in tests. Both return a **proposal**
/// (or `null` if the model's output could not be parsed); the orchestrator is
/// what validates it. Kept separate from [CoachClient] so the onboarding fakes
/// don't have to implement generation.
abstract interface class PlanClient {
  /// A proposed skeleton for [profile]. [violations] carries the machine codes
  /// from a prior failed attempt, fed back so the model can fix them.
  Future<PlanSkeleton?> proposeSkeleton({
    required RunnerProfile profile,
    List<String> violations,
  });

  /// A proposed week of sessions for the skeleton [slot].
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations,
  });

  /// A revision of [week] that honours the runner's natural-language [request]
  /// (e.g. "can't run Tuesday"). Returns the full revised week, or null if the
  /// model's output could not be parsed.
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  });
}
