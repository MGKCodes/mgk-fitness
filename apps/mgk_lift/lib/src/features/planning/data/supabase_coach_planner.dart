import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

// `Session` is also a gotrue type. Hidden rather than aliased so every use
// below still reads as the app's own session.
import '../../tracking/domain/session.dart';
import '../domain/intake_flow.dart';
import '../domain/plan_intake.dart';
import '../domain/plan_builder.dart';
import '../domain/coach_planner.dart';
import '../domain/plan_proposal.dart';

/// The planning half of the coach, via the same `coach` Edge Function.
///
/// Four surfaces, one function, and no model key anywhere in this app. What is
/// sent is deliberately thin: the intake answers and which week is being asked
/// for. **The training log is not sent** — the function reads it under this
/// caller's own JWT, so RLS scopes it and the app cannot describe a session
/// that did not happen.
///
/// The exception is [swap], which sends the session in progress. That is not a
/// record yet: the device owns it until it is finished, so there is nothing on
/// the server to read.
class SupabaseCoachPlanner implements CoachPlanner {
  SupabaseCoachPlanner(this._client);

  final SupabaseClient _client;

  @override
  Future<IntakeTurn> intake({
    required IntakeProgress progress,
    required List<PlannerTurn> history,
  }) async {
    final data = await _invoke(<String, Object?>{
      'surface': 'lift_intake',
      'slots': progress.plan.toJson(),
      // By IntakeField name. What is still open is not sent: the coach works
      // it out from `slots` after reading the lifter's latest message, in the
      // order its own instructions give, which is IntakeField's order (pinned
      // by `LIFT_INTAKE_FIELDS` in surfaces.ts). The `missing` list sent here
      // until 2026-10-07 was in a different order, and following it is what
      // made the coach ask one thing above options for another.
      'declined': <String>[for (final f in progress.declined) f.name],
      'history': <Map<String, Object?>>[
        for (final turn in history)
          <String, Object?>{
            'role': turn.fromCoach ? 'coach' : 'user',
            'text': turn.text,
          },
      ],
    });

    final extracted = data['extracted'];
    return IntakeTurn(
      reply: (data['reply'] as String? ?? '').trim(),
      asking: data['asking'] as String?,
      // Every turn returns every field, and null means "not learned this turn"
      // rather than "forget it" — which is why the caller merges rather than
      // replaces.
      extracted: extracted is Map<String, Object?>
          ? PlanIntake.fromJson(extracted)
          : const PlanIntake(),
    );
  }

  @override
  Future<PlanProposal> plan({
    required PlanIntake intake,
    required List<int> weekdays,
    required List<String> catalogue,
    List<String> violations = const <String>[],
  }) async {
    final data = await _invoke(<String, Object?>{
      'surface': 'lift_plan',
      'profile': intake.toJson(),
      'weekdays': weekdays,
      // The one input the function cannot read for itself: the catalogue lives
      // in the app. Sent filtered to what this lifter can actually use, both to
      // keep the prompt short and so the coach is never offered a machine they
      // do not have. Everything else the prompt needs -- the log, the memory,
      // the house guidance -- is read server-side and overwrites whatever is
      // sent here.
      'catalogue': catalogue.join(String.fromCharCode(10)),
      if (violations.isNotEmpty) 'violations': violations,
    });
    return PlanProposal.fromJson(data);
  }

  @override
  Future<SwapProposal> swap({
    required String message,
    required Session session,
  }) async {
    final data = await _invoke(<String, Object?>{
      'surface': 'lift_swap',
      'message': message,
      'session': <String, Object?>{
        'exercises': <Map<String, Object?>>[
          for (final exercise in session.exercises)
            <String, Object?>{
              'name': exercise.name,
              'sets': <Map<String, Object?>>[
                for (final set in exercise.sets)
                  <String, Object?>{'is_completed': set.isCompleted},
              ],
            },
        ],
      },
    });
    return SwapProposal.fromJson(data);
  }

  /// How long one call to the coach may take before it is treated as failed.
  ///
  /// **A request with no deadline is a screen with no way out.** Plan intake
  /// blocks the back gesture while a turn is in flight, deliberately — an
  /// abandoned turn is a paid call whose answer would have been merged into
  /// what the coach knows. That is only defensible if "in flight" ends. With no
  /// timeout anywhere on this path, a provider that accepts a connection and
  /// then says nothing left the lifter on a screen they could not leave.
  ///
  /// Generous rather than tight: these are two model calls deep and honestly
  /// slow, and killing a request that would have landed is its own failure.
  /// This is the boundary between "slow" and "never".
  static const Duration requestTimeout = Duration(seconds: 90);

  Future<Map<String, Object?>> _invoke(Map<String, Object?> body) async {
    if (_client.auth.currentUser == null) {
      throw const PlanException(PlanFailure.signedOut);
    }
    try {
      final res = await _client.functions
          .invoke('coach', body: body)
          .timeout(requestTimeout);
      final data = res.data;
      if (data is Map<String, Object?>) return data;
      if (data is Map) return data.cast<String, Object?>();
      // It answered, with something unusable: the server's fault.
      throw const PlanException(PlanFailure.serverError);
    } on FunctionException catch (e) {
      throw PlanException(_map(e));
    } on PlanException {
      rethrow;
    } on Object {
      throw const PlanException(PlanFailure.unavailable);
    }
  }

  /// The codes are the contract, not the bodies — the function never forwards
  /// an upstream error message, because those can carry our billing details.
  ///
  /// **Any other status is the server's fault, not the signal's.** A 502 means
  /// the function ran and the model's answer was unusable; calling that "could
  /// not reach your coach" sends somebody to check a connection that worked.
  /// Only no answer at all -- the catch-all in [_invoke] -- is [unavailable].
  static PlanFailure _map(FunctionException e) => switch (e.status) {
    401 => PlanFailure.signedOut,
    402 => PlanFailure.notEntitled,
    429 => PlanFailure.limitReached,
    _ => PlanFailure.serverError,
  };
}
