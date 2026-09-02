import '../domain/plan_validator.dart';
import '../domain/runner_profile.dart';
import '../domain/training_plan.dart';
import '../domain/week_adaptation.dart';
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

  Future<AdaptationProposal?> propose({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async {
    TrainingWeek? revised;
    try {
      revised = await _client.proposeAdaptation(
        week: week,
        slot: slot,
        profile: profile,
        request: request,
      );
    } on CoachLimitException {
      // Unlike generation there is no deterministic adaptation to fall back on,
      // so swallowing this would tell the runner the coach "couldn't adjust the
      // week" when the truth is they've spent their allowance. Let it through.
      rethrow;
    } on CoachNotEntitledException {
      // And the same for the door: "couldn't adjust the week" would describe a
      // fault, where the truth is that adjusting weeks is what the coach is.
      rethrow;
    } catch (_) {
      revised = null;
    }
    if (revised == null) return null;

    // The revision must still be a structurally sound week — but it is allowed
    // to depart from the slot, because departing from the slot is the entire
    // point of an adaptation the runner asked for. Validating against the
    // planning rules here would reject "make Sunday easier" for the crime of
    // making Sunday easier.
    final verdict = validateWeek(
      revised,
      slot,
      profile,
      rules: adaptationRules,
    );
    if (!verdict.isValid) throw AdaptationRefused(verdict.violations);

    final changes = diffWeek(week, revised);
    if (changes.isEmpty) return null; // nothing actually changed
    return AdaptationProposal(week: revised, changes: changes);
  }
}
