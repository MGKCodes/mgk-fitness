import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

// `Session` is also a gotrue type. Hidden rather than aliased so every use
// below still reads as the app's own session.
import '../../tracking/domain/session.dart';
import '../domain/plan.dart';
import '../domain/plan_generator.dart';
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
    required PlanIntake known,
    required List<PlannerTurn> history,
  }) async {
    final data = await _invoke(<String, Object?>{
      'surface': 'lift_intake',
      'slots': known.toJson(),
      'missing': known.missing,
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
      // Every turn returns every field, and null means "not learned this turn"
      // rather than "forget it" — which is why the caller merges rather than
      // replaces.
      extracted: extracted is Map<String, Object?>
          ? PlanIntake.fromJson(extracted)
          : const PlanIntake(),
    );
  }

  @override
  Future<List<PlanWeek>> skeleton({
    required PlanIntake intake,
    List<String> violations = const <String>[],
  }) async {
    final data = await _invoke(<String, Object?>{
      'surface': 'lift_skeleton',
      'profile': intake.toJson(),
      if (violations.isNotEmpty) 'violations': violations,
    });

    final weeks = data['weeks'];
    if (weeks is! List) return const <PlanWeek>[];
    return <PlanWeek>[
      for (final w in weeks)
        if (w is Map<String, Object?>)
          PlanWeek(
            number: (w['index'] as num?)?.toInt() ?? 0,
            phase: PlanPhase.fromWire(w['phase'] as String? ?? 'base'),
            intent: (w['intent'] as String?)?.trim(),
          ),
    ]..removeWhere((PlanWeek w) => w.number < 1);
  }

  @override
  Future<WeekProposal> week({
    required PlanIntake intake,
    required PlanWeek slot,
    List<String> violations = const <String>[],
  }) async {
    final data = await _invoke(<String, Object?>{
      'surface': 'lift_week',
      'profile': intake.toJson(),
      'slot': <String, Object?>{
        'week': slot.number,
        'phase': slot.phase.wire,
        'intent': slot.intent,
        'is_deload': slot.isDeload,
      },
      if (violations.isNotEmpty) 'violations': violations,
    });
    return WeekProposal.fromJson(data);
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

  Future<Map<String, Object?>> _invoke(Map<String, Object?> body) async {
    if (_client.auth.currentUser == null) {
      throw const PlanException(PlanFailure.signedOut);
    }
    try {
      final res = await _client.functions.invoke('coach', body: body);
      final data = res.data;
      if (data is Map<String, Object?>) return data;
      if (data is Map) return data.cast<String, Object?>();
      throw const PlanException(PlanFailure.unavailable);
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
  static PlanFailure _map(FunctionException e) => switch (e.status) {
    401 => PlanFailure.signedOut,
    402 => PlanFailure.notEntitled,
    429 => PlanFailure.limitReached,
    _ => PlanFailure.unavailable,
  };
}
