/// Coach failures the UI is expected to render.
///
/// Kept apart from `coach_service.dart` so the orchestrator ([PlanService]) and
/// the widgets can catch them without pulling the Supabase client into their
/// import graph — `plan_service.dart` stays pure and testable against fakes.
library;

/// A user-presentable coach failure. [message] is safe to show directly.
class CoachException implements Exception {
  const CoachException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The runner hit their own rate limit or spend cap on the coach.
///
/// Distinct from [CoachException] because it is **not** a failure to retry: the
/// window has to pass first, so a second attempt is guaranteed to be refused
/// too. Callers that would otherwise fall back silently need to be able to tell
/// "you've used your allowance" apart from "the model produced garbage" —
/// they're the same `null` otherwise, and the runner gets a provisional week
/// with no idea why.
class CoachLimitException implements CoachException {
  const CoachLimitException({
    required this.scope,
    this.retryAfterSeconds,
    required this.spendCapped,
  });

  /// Which ceiling bound — a surface name, `daily_requests` or `daily_spend`.
  final String scope;

  /// Seconds until the window clears, when the function reported it.
  final int? retryAfterSeconds;

  /// True for the credit cap, false for a request-rate limit.
  final bool spendCapped;

  @override
  String get message {
    final wait = _waitText();
    if (spendCapped) {
      return "You've used your coach allowance for now."
          '${wait == null ? '' : ' Try again in $wait.'}';
    }
    return "That's a lot of coaching in a short time."
        '${wait == null ? ' Try again shortly.' : ' Try again in $wait.'}';
  }

  String? _waitText() {
    final s = retryAfterSeconds;
    if (s == null || s <= 0) return null;
    if (s < 60) return '$s seconds';
    final minutes = (s / 60).ceil();
    if (minutes < 60) return '$minutes minute${minutes == 1 ? '' : 's'}';
    final hours = (minutes / 60).ceil();
    return '$hours hour${hours == 1 ? '' : 's'}';
  }

  @override
  String toString() => message;
}

/// The coach is a paid tier and this runner has not bought it.
///
/// The function's `not_entitled` refusal, which arrives as a 402
/// ([ADR-0030](../../../../docs/decisions/0030-the-coach-is-the-paid-half.md)).
///
/// **Distinct from every other coach failure because it is not one.** Nothing
/// has gone wrong: the runner is at a door rather than at a fault, and the
/// difference has to survive all the way to the widget or it renders as "The
/// coach hit a problem. Please try again." — which is a lie that invites a
/// retry guaranteed to fail, and makes a working paywall look like broken
/// software. Retrying is not the answer; buying is.
///
/// It is deliberately **not** a [CoachLimitException]. That one means "come
/// back later", and this one never clears on its own.
class CoachNotEntitledException implements CoachException {
  const CoachNotEntitledException();

  @override
  String get message =>
      'A plan and the coach are part of the subscription. Your runs, your log '
      'and your records are always free.';

  @override
  String toString() => message;
}

/// The signed-in runner has not agreed to their training going to the AI
/// provider, so nothing was sent.
///
/// Thrown by `CoachService` **before** a request is built, on every surface.
/// The screens ask first, and this is what makes asking the rule rather than
/// a habit: a caller added next month that forgets to ask still cannot send.
///
/// Neither a fault nor a door, for the same reason [CoachNotEntitledException]
/// is not a fault. Retrying cannot help and paying cannot either; the answer
/// is the question, which the UI puts back in front of them.
class CoachConsentRequiredException implements CoachException {
  const CoachConsentRequiredException();

  @override
  String get message =>
      'Your coach needs your permission before anything is sent. Nothing was '
      'sent.';

  @override
  String toString() => message;
}
