import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'coach_errors.dart';

import '../domain/intake_conversation.dart';
import '../domain/intake_slots.dart';
import '../domain/runner_profile.dart';
import '../domain/training_plan.dart';
import 'coach_errors.dart';
import 'coach_client.dart';
import '../../history/domain/run_draft.dart';
import 'coach_mappers.dart';
import 'plan_client.dart';
import 'plan_mappers.dart';

/// The single client-side entry point to the AI coach. Every call goes to the
/// `coach` Edge Function, authenticated with the user's Supabase session — the
/// provider key lives only on the server (docs/decisions/0007). The function
/// returns a structured proposal; the caller re-validates before using it.
///
/// Implements every seam: [CoachClient] (conversational intake),
/// [CoachChatClient] (the open conversation) and [PlanClient] (skeleton/week
/// generation).
class CoachService
    implements
        CoachClient,
        CoachChatClient,
        CoachSummariseClient,
        CoachLogRunClient,
        CoachEditRunClient,
        CoachSetGoalClient,
        PlanClient {
  CoachService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Debug-only: the model this build asks the coach to use, or null to let the
  /// server decide. Set from the Settings model picker (`lib/src/dev/`).
  ///
  /// A static rather than a constructor argument because it is switched at
  /// runtime from a leaf of Settings, while the services that read it are built
  /// in several places (the shell, the plan orchestrator, the preview harness).
  /// Threading it through all of them to serve a debug tool would put dev
  /// plumbing in the signature of production code.
  ///
  /// Sending it is harmless on its own: the function honours a named model only
  /// when it appears in `COACH_MODEL_ALLOWLIST`, and ignores the field entirely
  /// when that secret is unset. The `kDebugMode` guard below is the second lock
  /// — a release build never sends the field at all, so a shipped app can never
  /// be the thing choosing what an account pays per token.
  static String? debugModelOverride;

  /// The model field to merge into a request body, if any.
  static Map<String, dynamic> get _modelField {
    final id = debugModelOverride;
    if (!kDebugMode || id == null || id.isEmpty) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{'model': id};
  }

  /// One onboarding turn: send the running slot state and the conversation so
  /// far, get back the coach's reply and the slots it extracted this turn. The
  /// caller merges the extraction into its [IntakeSlots] and decides when the
  /// conversation is done — the model never holds the slot state.
  @override
  Future<IntakeTurn> intake({
    required IntakeSlots slots,
    required List<IntakeMessage> history,
  }) async => intakeTurnFromResponse(
    await _invokeConversation(<String, dynamic>{
      'surface': 'intake',
      'slots': intakeSlotsToContext(slots),
      'missing': slots.missingRequired.toList(),
      'history': <Map<String, String>>[
        for (final m in history) {'role': m.role, 'text': m.text},
      ],
    }),
  );

  /// One turn of the open conversation.
  ///
  /// The brief is prose, not a struct — see `CoachBrief`. The history omits
  /// [message] because the contract keeps "what they just said" separate from
  /// "what has been said".
  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async => chatTurnFromResponse(
    await _invokeConversation(<String, dynamic>{
      'surface': 'chat',
      'brief': brief,
      'history': <Map<String, String>>[
        for (final m in history) {'role': m.role, 'text': m.text},
      ],
      'message': message,
    }),
  );

  @override
  Future<String?> summarise({
    String? previous,
    required List<ChatMessage> transcript,
  }) async {
    // The *swallowing* invoker, deliberately. Summarising is housekeeping the
    // runner never asked for; a failure means the existing memory stands, and
    // there is nobody to show an error to.
    final data = await _invokeSurface('summarise', <String, dynamic>{
      if (previous != null && previous.isNotEmpty) 'previous': previous,
      'transcript': <Map<String, String>>[
        for (final m in transcript) {'role': m.role, 'text': m.text},
      ],
    });
    final summary = data?['summary'];
    return summary is String ? summary : null;
  }

  /// Reads a run out of what the runner said, as a draft to confirm.
  ///
  /// Returns null when nothing usable came back — a swallowing call, like
  /// [summarise], because the coach has already replied and the runner is not
  /// waiting on an error. The caller says so in the transcript instead.
  ///
  /// **The draft is not checked here.** `RunDraft.issues` is the check, and it
  /// runs where the result is shown: a run that fails validation must be
  /// refused in front of the runner rather than silently dropped, or the coach
  /// appears to have logged something it did not.
  @override
  Future<RunDraft?> logRun(String request) async {
    final data = await _invokeSurface('log_run', <String, dynamic>{
      'request': request,
    });
    return data == null ? null : runDraftFromResponse(data);
  }

  /// Reads a correction out of what the runner said.
  ///
  /// Swallowing like [logRun]: the coach has already replied, so a failure is
  /// said in the transcript rather than thrown. Which run this refers to is not
  /// resolved here — that needs the runner's recent runs, which live in the
  /// shell, and refusing an ambiguous day is the caller's job.
  @override
  Future<RunCorrection?> editRun(String request) async {
    final data = await _invokeSurface('edit_run', <String, dynamic>{
      'request': request,
    });
    return data == null ? null : runCorrectionFromResponse(data);
  }

  /// What the runner said about their target.
  ///
  /// Swallowing like the other two extractors: nothing usable back means no
  /// card, and the reply the coach already gave still stands. The refusal that
  /// matters for this surface is not here anyway — it is `GoalDraft`, in front
  /// of the runner, because what this returns can supersede a whole block.
  @override
  Future<GoalChange?> setGoal(String request) async {
    final data = await _invokeSurface('set_goal', <String, dynamic>{
      'request': request,
    });
    return data == null ? null : goalChangeFromResponse(data);
  }

  /// Invokes a **conversational** surface, where a failure is the runner's
  /// problem to see rather than something to retry behind their back.
  ///
  /// The opposite of [_invokeSurface]: generation can fall back on a
  /// deterministic plan, so it swallows failures and returns null. A turn of
  /// conversation has no fallback — silence in a chat is indistinguishable from
  /// being ignored — so everything here throws a message the UI can print.
  /// How long one call to the coach may take before it counts as failed.
  ///
  /// **Nothing on this path had a deadline.** The plan reveal sets
  /// `canPop: false` for the whole of its build -- correctly, there is nothing
  /// behind it to go back to -- and its only exits are the buttons on the
  /// failed and revealed states. Both need the call to *return*. A provider
  /// that accepted the connection and then said nothing produced neither, and
  /// the screen it stranded the runner on had no way out at all.
  ///
  /// Its own comment called that screen "never a dead end". This is what makes
  /// that true.
  static const Duration requestTimeout = Duration(seconds: 90);

  Future<Map<String, dynamic>> _invokeConversation(
    Map<String, dynamic> body,
  ) async {
    final Object? data;
    try {
      final res = await _client.functions
          .invoke('coach', body: <String, dynamic>{...body, ..._modelField})
          .timeout(requestTimeout);
      data = res.data;
    } on TimeoutException {
      // Surfaced rather than swallowed. The plan reveal blocks the back gesture
      // for the whole of its build, and its failure state is the only way off
      // that screen -- so a provider that goes quiet has to reach it.
      throw const CoachException(
        'Your coach is taking longer than it should. Try again.',
      );
    } on FunctionException catch (e) {
      // Non-2xx from the function; its body (with `error`) rides on `details`.
      final limit = _limitFrom(e.details);
      if (limit != null) throw limit;
      throw CoachException(_messageForError(_codeFrom(e.details)));
    }

    if (data is! Map<String, dynamic>) {
      throw const CoachException('The coach returned an unexpected response.');
    }
    if (data['error'] != null) {
      final limit = _limitFrom(data);
      if (limit != null) throw limit;
      throw CoachException(_messageForError(data['error']));
    }
    return data;
  }

  @override
  Future<PlanSkeleton?> proposeSkeleton({
    required RunnerProfile profile,
    List<String> violations = const <String>[],
  }) async {
    final data = await _invokeSurface('skeleton', <String, dynamic>{
      'profile': runnerProfileToJson(profile),
      'violations': violations,
    });
    return data == null ? null : planSkeletonFromJson(data);
  }

  @override
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations = const <String>[],
  }) async {
    final data = await _invokeSurface('week', <String, dynamic>{
      'slot': skeletonWeekToJson(slot),
      'profile': runnerProfileToJson(profile),
      'violations': violations,
    });
    return data == null
        ? null
        : trainingWeekFromJson(data, skeletonIndex: slot.index);
  }

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async {
    final data = await _invokeSurface('adapt', <String, dynamic>{
      'week': trainingWeekToJson(week),
      'slot': skeletonWeekToJson(slot),
      'profile': runnerProfileToJson(profile),
      'request': request,
    });
    return data == null
        ? null
        : trainingWeekFromJson(data, skeletonIndex: slot.index);
  }

  /// Invokes a generation surface, returning the parsed JSON object or null on
  /// any failure (network, function error, non-map). The orchestrator treats
  /// null as a failed attempt and retries or falls back — generation never
  /// throws at the runner.
  ///
  /// The one exception is the runner's own rate limit or spend cap, which throws
  /// [CoachLimitException]. Collapsing that into null would both hide the reason
  /// from the runner and burn a retry on a request certain to be refused again.
  Future<Map<String, dynamic>?> _invokeSurface(
    String surface,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _client.functions
          .invoke(
            'coach',
            body: <String, dynamic>{
              'surface': surface,
              ...payload,
              ..._modelField,
            },
          )
          .timeout(requestTimeout);
      final data = res.data;
      if (data is Map<String, dynamic> && data['error'] == null) return data;
      final limit = _limitFrom(data);
      if (limit != null) throw limit;
      return null;
    } on TimeoutException {
      // This invoker's contract is "null means fall back to the deterministic
      // path", and a hung provider is exactly that case.
      return null;
    } on FunctionException catch (e) {
      final limit = _limitFrom(e.details);
      if (limit != null) throw limit;
      return null;
    }
  }

  static String? _codeFrom(Object? details) {
    if (details is Map && details['error'] != null) {
      return details['error'].toString();
    }
    return null;
  }

  /// A [CoachLimitException] when the body is one of the function's two limit
  /// refusals, else null. See supabase/functions/coach — the contract is
  /// `{error, scope, retry_after_seconds}` on a 429.
  static CoachLimitException? _limitFrom(Object? details) {
    if (details is! Map) return null;
    final code = details['error']?.toString();
    if (code != 'rate_limited' && code != 'spend_cap_reached') return null;
    final retry = details['retry_after_seconds'];
    return CoachLimitException(
      scope: details['scope']?.toString() ?? code!,
      retryAfterSeconds: retry is num ? retry.round() : null,
      spendCapped: code == 'spend_cap_reached',
    );
  }

  static String _messageForError(Object? code) {
    switch (code) {
      case 'refused':
        return 'The coach could not work with that. Try rephrasing.';
      case 'coach_not_configured':
        return 'The coach is not set up yet.';
      case 'unauthorized':
        return 'Please sign in again to use the coach.';
      default:
        return 'The coach hit a problem. Please try again.';
    }
  }
}
