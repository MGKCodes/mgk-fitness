import '../domain/plan_builder.dart';
import '../domain/plan_shape.dart';
import '../domain/plan_validator.dart';
import '../domain/runner_profile.dart';
import '../domain/training_plan.dart';
import 'coach_errors.dart';
import 'plan_client.dart';

/// Where a plan (or week) came from.
enum PlanSource {
  /// The model proposed it and it passed validation.
  model,

  /// The model failed twice; built deterministically from the skeleton.
  fallback,

  /// Decided by a rule in Dart, and the model was never asked: race week. Not
  /// a second choice, so unlike [fallback] it is kept.
  rule,
}

/// A generated plan artefact plus how it was produced.
class PlanResult<T> {
  const PlanResult(
    this.plan,
    this.source, {
    required this.modelAttempts,
    this.limit,
  });

  final T plan;
  final PlanSource source;

  /// How many model attempts were made (0 when the client wasn't reached).
  final int modelAttempts;

  /// Set when the fallback was used because the runner hit their rate limit or
  /// spend cap, rather than because the model failed. Carried so the UI can say
  /// *why* the plan is provisional instead of leaving the runner to guess.
  final CoachLimitException? limit;

  bool get isFallback => source == PlanSource.fallback;
}

/// The generation orchestrator — **the model proposes, the validator disposes**
/// (plan-generation.md). Each artefact is asked of the model, validated, and on
/// failure re-requested with the violated constraints fed back explicitly.
/// After [maxModelAttempts] failures it falls back to the deterministic builder,
/// so a runner always gets a structurally sound plan — even if the model is
/// down, slow, or producing garbage.
class PlanService {
  PlanService({
    required PlanClient client,
    DateTime Function() now = DateTime.now,
    this.maxModelAttempts = 2,
    this.rules,
  }) : _client = client,
       _now = now;

  final PlanClient _client;
  final DateTime Function() _now;
  final int maxModelAttempts;

  /// Overrides the per-shape rule set. Null means each plan is judged by the
  /// rules for its own shape (ADR-0011).
  final PlanRules? rules;

  /// The plan arc. Validated against the skeleton invariants; deterministic
  /// fallback if the model can't produce a valid one.
  Future<PlanResult<PlanSkeleton>> generateSkeleton(
    RunnerProfile profile,
  ) async {
    var violations = const <String>[];
    var attempts = 0;
    for (var attempt = 1; attempt <= maxModelAttempts; attempt++) {
      attempts = attempt;
      final PlanSkeleton? proposal;
      try {
        proposal = await _safe(
          () =>
              _client.proposeSkeleton(profile: profile, violations: violations),
        );
      } on CoachLimitException catch (e) {
        return PlanResult(
          buildSkeleton(profile, now: _now()),
          PlanSource.fallback,
          modelAttempts: attempt - 1,
          limit: e,
        );
      }
      if (proposal != null) {
        final result = validateSkeleton(
          proposal,
          profile,
          rules: rules ?? PlanRules.forShape(shapeOf(profile)),
        );
        if (result.isValid) {
          return PlanResult(proposal, PlanSource.model, modelAttempts: attempt);
        }
        violations = _codes(result);
      } else {
        violations = _unparseable('skeleton');
      }
    }
    return PlanResult(
      buildSkeleton(profile, now: _now()),
      PlanSource.fallback,
      modelAttempts: attempts,
    );
  }

  /// One week of sessions for its skeleton [slot]. Validated against the week
  /// invariants; deterministic (provisional) fallback if the model fails.
  Future<PlanResult<TrainingWeek>> generateWeek(
    SkeletonWeek slot,
    RunnerProfile profile, {
    int? raceWeekday,
    DateTime? weekStart,
  }) async {
    // **Race week is not proposed.** It has one right shape whoever the
    // runner is (see [buildRaceWeek]), and a model asked for it had to satisfy
    // a slot that still carried a long run, which it could only do by putting
    // one the day before the race.
    if (raceWeekday != null) {
      return PlanResult(
        buildRaceWeek(slot, profile, raceWeekday: raceWeekday),
        PlanSource.rule,
        modelAttempts: 0,
      );
    }
    var violations = const <String>[];
    var attempts = 0;
    for (var attempt = 1; attempt <= maxModelAttempts; attempt++) {
      attempts = attempt;
      final TrainingWeek? proposal;
      try {
        proposal = await _safe(
          () => _client.proposeWeek(
            slot: slot,
            profile: profile,
            violations: violations,
          ),
        );
      } on CoachLimitException catch (e) {
        return PlanResult(
          buildFallbackWeek(slot, profile),
          PlanSource.fallback,
          modelAttempts: attempt - 1,
          limit: e,
        );
      }
      if (proposal != null) {
        final result = validateWeek(
          proposal,
          slot,
          profile,
          rules: rules ?? PlanRules.forShape(shapeOf(profile)),
          // Opt-in on `validateWeek`'s side (see its doc): a caller with no
          // calendar leaves this null and nothing changes. A caller that has
          // one is what turns on `session_in_the_past`, the model proposing a
          // run on a day already gone (EDGE-17). Race week never reaches this
          // far.
          weekStart: weekStart,
          now: _now(),
        );
        if (result.isValid) {
          return PlanResult(proposal, PlanSource.model, modelAttempts: attempt);
        }
        violations = _codes(result);
      } else {
        violations = _unparseable('week');
      }
    }
    return PlanResult(
      buildFallbackWeek(slot, profile),
      PlanSource.fallback,
      modelAttempts: attempts,
    );
  }

  /// A network error or thrown proposal is just a failed attempt — it must not
  /// deny the runner a plan, so it degrades to the fallback like any other miss.
  ///
  /// A [CoachLimitException] is deliberately **not** swallowed: the runner's
  /// window has to pass before another request can succeed, so retrying spends
  /// an attempt on a certain refusal. It propagates to the caller, which falls
  /// back deterministically at once.
  Future<T?> _safe<T>(Future<T?> Function() propose) async {
    try {
      return await propose();
    } on CoachLimitException {
      rethrow;
    } on CoachNotEntitledException {
      // Same reason as the limit above, and a stronger one. `null` here means
      // "the model failed, build the deterministic plan instead", and handing
      // an unentitled runner a free fallback plan would give away the thing the
      // subscription is for while telling them nothing.
      rethrow;
    } catch (_) {
      return null;
    }
  }

  static List<String> _codes(ValidationResult result) =>
      result.violations.map((v) => '${v.code}: ${v.message}').toList();

  static List<String> _unparseable(String what) => <String>[
    'unparseable: the response was not a valid $what',
  ];
}
