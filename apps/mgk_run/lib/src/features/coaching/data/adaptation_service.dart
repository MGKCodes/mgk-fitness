import '../domain/plan_builder.dart';
import '../domain/plan_validator.dart';
import '../domain/runner_profile.dart';
import '../domain/training_plan.dart';
import '../domain/week_adaptation.dart';
import '../domain/week_progress.dart';
import 'coach_errors.dart';
import 'plan_client.dart';

/// A proposed adaptation the runner can approve: the revised week and the
/// derived list of changes to show them.
class AdaptationProposal {
  const AdaptationProposal({required this.week, required this.changes});

  final TrainingWeek week;
  final List<SessionChange> changes;
}

/// The validator rejected a revision the model *did* produce.
///
/// Distinct from "no proposal came back" on purpose. Both used to surface as
/// null, and null gets told to the runner as *"try telling me what you want
/// differently"* — which is advice that cannot work when the reason is a fact
/// about their own week. Asked to move a session to a day they said they were
/// not free, they were invited to rephrase a request no rephrasing would fix.
///
/// So the reason travels. The validator already knew it; it was being thrown
/// away one layer below the person who could act on it.
class AdaptationRefused implements Exception {
  const AdaptationRefused(this.violations);

  final List<Violation> violations;

  /// The refusal in the runner's terms, not the validator's.
  ///
  /// One reason, not a list: a runner reading three simultaneous objections
  /// learns less than one they can answer. The order is by what they can
  /// actually do something about — an unavailable day is a sentence away from
  /// fixed, an overlong long run is not.
  String get message {
    for (final code in _spoken.keys) {
      if (violations.any((v) => v.code == code)) return _spoken[code]!;
    }
    return "That change would break the week, so I've left it as it was.";
  }

  static const Map<String, String> _spoken = <String, String>{
    'unavailable_day':
        "That would put a session on a day you said you can't run. Tell me "
        "which day suits and I'll move it there.",
    'session_count':
        'That would give you more run days than you asked for. I can swap a '
        'session rather than add one — say which.',
    'strength_count':
        'That adds more strength days than you asked for. Say which one to '
        "drop and I'll rework it.",
    'back_to_back_hard':
        'That would stack two hard days together. Give me a rest day between '
        "them and I'll do it.",
    'long_run_fraction':
        'That would make the long run too big a share of the week. Shrink it '
        "or add elsewhere and I'll take another look.",
    'long_run_ceiling':
        "That long run is further than I'll write for you at this stage.",
    // Last, because the order is by what the runner can do something about and
    // this one is not their doing at all — it is the model trying to rewrite a
    // day they have already run. It still has to be here rather than falling
    // through to the generic line: "that would break the week" tells someone
    // nothing, where naming the day at least says which part of their week the
    // coach was arguing with.
    'session_already_done':
        "That would change a session you've already run, so I've left the week "
        'alone. Tell me what you want to do with the days that are left.',
  };
}

/// Turns a natural-language request into a **validated** week revision — the
/// model proposes, the validator disposes (plan-generation.md). The service
/// only proposes; the runner approves before it is applied.
///
/// Two ways it declines, and they are not the same thing to the person waiting:
/// **null** when the model gave back nothing usable, so rephrasing is worth a
/// try; [AdaptationRefused] when it gave back a week the validator would not
/// stand behind, which carries a reason the runner can act on.
///
/// Given a `soFar` there is a third answer before either of those. A week the
/// model could not revise, in which the runner has plainly departed from the
/// plan, gets a deterministic refit rather than a null — the situation has an
/// answer even when the conversation does not.
class AdaptationService {
  AdaptationService({
    required PlanClient client,
    this.rules = const PlanRules(),
    this.adaptationRules = const PlanRules.adaptation(),
  }) : _client = client;

  final PlanClient _client;

  /// The planning rules. Used for anything that must match the plan; a revision
  /// the runner asked for is judged by [adaptationRules] instead.
  final PlanRules rules;

  /// The relaxed rules a sanctioned deviation is held to.
  final PlanRules adaptationRules;

  /// [soFar] is what has already happened in [week] — which sessions were run,
  /// which went, and any run on a day the plan asked nothing of.
  ///
  /// Optional, and everything works without it exactly as it did before: the
  /// caller that owns the calendar is the one that can honestly say what the
  /// week has done, including the `since` floor that stops a plan being held to
  /// days that predate it. Given it, three things change and they reinforce each
  /// other — the model is *told* what happened so it gets the revision right,
  /// the validator *refuses* a revision that rewrites a completed session, and a
  /// week the model could not revise at all still gets a deterministic refit
  /// rather than a shrug.
  Future<AdaptationProposal?> propose({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
    WeekAsRun? soFar,
    // Opt-in, for the reason `validateWeek`'s own doc gives: the plan model
    // carries no dates, so only a caller holding the `StoredPlan` can supply
    // these, and one that cannot is unchanged by leaving them null. Without
    // them `session_on_race_day` never ran here at all (EDGE-17) — a
    // revision could move a session onto race day and nothing would object.
    DateTime? weekStart,
    DateTime? now,
  }) async {
    TrainingWeek? revised;
    try {
      // The richer call when the client offers it — see [WeekAwarePlanClient]
      // for why it is offered rather than required.
      final client = _client;
      revised = soFar != null && client is WeekAwarePlanClient
          ? await client.proposeRefit(
              week: week,
              slot: slot,
              profile: profile,
              request: request,
              soFar: soFar,
            )
          : await client.proposeAdaptation(
              week: week,
              slot: slot,
              profile: profile,
              request: request,
            );
    } on CoachLimitException {
      // Swallowing this would tell the runner the coach "couldn't adjust the
      // week" when the truth is they've spent their allowance. Let it through.
      //
      // Still true now that there *is* a deterministic adaptation below. Handing
      // them a refit instead would hide the reason behind a week they did not
      // ask for, and the next thing they do is ask again — against a limit they
      // still have no idea they have hit.
      rethrow;
    } on CoachNotEntitledException {
      // And the same for the door: "couldn't adjust the week" would describe a
      // fault, where the truth is that adjusting weeks is what the coach is.
      rethrow;
    } catch (_) {
      revised = null;
    }
    if (revised == null) {
      return _refit(week, slot, profile, soFar, weekStart: weekStart, now: now);
    }

    // The revision must still be a structurally sound week — but it is allowed
    // to depart from the slot, because departing from the slot is the entire
    // point of an adaptation the runner asked for. Validating against the
    // planning rules here would reject "make Sunday easier" for the crime of
    // making Sunday easier.
    //
    // [soFar] adds the one rule that is not about the slot at all: a session the
    // runner has already run may not be moved, resized or dropped.
    final verdict = validateWeek(
      revised,
      slot,
      profile,
      rules: adaptationRules,
      soFar: soFar,
      weekStart: weekStart,
      now: now,
    );
    if (!verdict.isValid) throw AdaptationRefused(verdict.violations);

    final changes = diffWeek(week, revised);
    if (changes.isEmpty) return null; // nothing actually changed
    return AdaptationProposal(week: revised, changes: changes);
  }

  /// The deterministic answer, for when the model gave back nothing usable.
  ///
  /// This used to be a flat null, and null reaches the runner as *"try telling
  /// me what you want differently"* — advice that cannot work when the coach is
  /// unreachable rather than confused, and that is doubly hollow when their week
  /// has plainly diverged from the plan and the app can see exactly how.
  ///
  /// **Only when the week has actually diverged.** [refitWeek] answers a
  /// *situation*, not a sentence: it knows nothing about "make Sunday easier"
  /// and would rearrange a perfectly on-track week in reply to it, which is the
  /// generic reshuffle this whole change exists to stop. With nothing missed,
  /// waved off or run off-plan there is no situation to answer, so the null
  /// stands and the invitation to rephrase is honest.
  ///
  /// Held to the same rules as the model's work, because a fallback nobody
  /// checks is how a fallback starts being wrong. It fails *quietly* rather than
  /// as an [AdaptationRefused]: the runner did not ask for this week and cannot
  /// rephrase their way out of a refusal about it.
  AdaptationProposal? _refit(
    TrainingWeek week,
    SkeletonWeek slot,
    RunnerProfile profile,
    WeekAsRun? soFar, {
    DateTime? weekStart,
    DateTime? now,
  }) {
    if (soFar == null || !soFar.hasDiverged) return null;

    final refitted = refitWeek(
      week: week,
      slot: slot,
      profile: profile,
      soFar: soFar,
    );
    final verdict = validateWeek(
      refitted,
      slot,
      profile,
      rules: adaptationRules,
      soFar: soFar,
      weekStart: weekStart,
      now: now,
    );
    if (!verdict.isValid) return null;

    final changes = diffWeek(week, refitted);
    if (changes.isEmpty) return null;
    return AdaptationProposal(week: refitted, changes: changes);
  }
}
