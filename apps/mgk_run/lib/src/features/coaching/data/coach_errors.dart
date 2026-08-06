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
