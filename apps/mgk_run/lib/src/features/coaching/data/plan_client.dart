import '../domain/runner_profile.dart';
import '../domain/training_plan.dart';
import '../domain/week_progress.dart';

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
  ///
  /// [raceWeekday] is the weekday race day falls on, for the week that
  /// contains it. **No longer sent.** Race week is built by rule and never
  /// proposed (ADR-0044), so [PlanService] has no race week to ask about. The
  /// parameter stays because the deployed coach function still reads it, and
  /// a build already on a phone still sends it.
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations,
    int? raceWeekday,
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

/// The adaptation seam, widened by **what has already happened this week**.
///
/// A separate interface rather than another argument on
/// [PlanClient.proposeAdaptation], and the reason is who implements it. Almost
/// every [PlanClient] in this app is a stand-in — the web preview, the store
/// tests, the widget tests — and most of them exist to answer a different method
/// entirely and return null from this one. Widening the shared method would make
/// each of them declare a fact they have no opinion about and never read.
///
/// So the richer call is *offered* rather than required. [AdaptationService]
/// takes it when the client has it and falls back to the plain call when it does
/// not — and nothing that protects the runner rides on the choice: the
/// `session_already_done` rule in `plan_validator.dart` and the deterministic
/// `refitWeek` are both in Dart and hold whichever call was made. What the
/// richer call buys is a model that gets it right the first time instead of
/// being refused and falling through.
abstract interface class WeekAwarePlanClient implements PlanClient {
  /// A revision of [week] that honours [request] **and** what [soFar] says has
  /// already happened in the week: the sessions already run stay exactly as they
  /// are, and only what remains is refitted around them.
  ///
  /// Returns the full revised week, or null if the model's output could not be
  /// parsed — the same contract as [PlanClient.proposeAdaptation], because the
  /// caller's fallback is the same either way.
  Future<TrainingWeek?> proposeRefit({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
    required WeekAsRun soFar,
  });
}
