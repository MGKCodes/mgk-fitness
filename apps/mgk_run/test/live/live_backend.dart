import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_run/src/features/coaching/data/coach_errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared setup for the `live` tests — the ones that run against the real
/// project rather than a fake.
///
/// A separate client rather than `Supabase.initialize`: the singleton wants
/// shared_preferences for session storage, which is a plugin, and every class
/// under test takes an injectable client precisely so this is possible.
Future<SupabaseClient> signedInClient() async {
  final config = AppConfig.current;
  final client = SupabaseClient(
    config.supabaseUrl,
    config.supabasePublishableKey,
  );
  final account = config.devAccounts.first;
  await client.auth.signInWithPassword(
    email: account.email,
    password: account.password,
  );
  expect(
    client.auth.currentUser,
    isNotNull,
    reason: 'could not sign in as the dev account',
  );
  return client;
}

/// True when this run was given real config. Live tests skip loudly without it.
bool get liveConfigured => AppConfig.current.isConfigured;

const String liveSkipReason =
    'needs a real backend: flutter test --tags live '
    '--dart-define-from-file=config/app_config.json';

/// Runs [body], and treats the runner's own allowance running out as
/// **inconclusive rather than failed**.
///
/// These tests hit the real limiter, which is the point — but it means running
/// the suite twice inside five minutes exhausts the chat allowance (15 per 5
/// minutes) and the skeleton allowance (6 an hour), and every test after that
/// goes red. A suite that fails because you ran it twice is a suite people
/// learn to ignore, which costs more than the coverage is worth.
///
/// So the distinction is made explicit: **"the feature is broken" is a failure;
/// "I could not test it just now" is a skip.** A `CoachLimitException` is the
/// limiter working correctly, so it can never mean the thing under test is
/// wrong. It is reported, not swallowed, so a run where everything skipped
/// cannot be mistaken for a run where everything passed.
Future<void> live(Future<void> Function() body) async {
  try {
    await body();
  } on CoachLimitException catch (e) {
    markTestSkipped('allowance spent (${e.scope}) — inconclusive, not failed');
  }
}

/// The same rule for the generation path, which reports a spent allowance
/// **in the result rather than by throwing** — `PlanService` catches
/// `CoachLimitException` and hands back the deterministic plan with `limit` set,
/// because a runner who has spent their allowance should still get a plan.
///
/// So [live] alone cannot see it, and a limited run looked exactly like "the
/// model was never called" — which is the one thing these tests exist to
/// detect. Returns true when the caller should stop and let the test skip.
bool spentAllowance(CoachLimitException? limit) {
  if (limit == null) return false;
  markTestSkipped(
    'allowance spent (${limit.scope}) — inconclusive, not failed',
  );
  return true;
}
