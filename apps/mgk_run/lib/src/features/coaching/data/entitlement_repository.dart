import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/coach_access.dart';
import '../domain/coach_subscription.dart';

/// What this runner has bought, read so the app can **draw** the right thing.
///
/// ## This is not the gate
///
/// The gate is `tierFor` in `supabase/functions/coach`, which resolves the same
/// row under `service_role` and refuses a request that has not paid for it
/// ([ADR-0030](../../../../docs/decisions/0030-the-coach-is-the-paid-half.md)).
/// A client asserting an entitlement is a claim, not a fact, and
/// [CoachAccess]'s own doc says nothing here is load-bearing for anything but
/// what is drawn.
///
/// So what is this for? **Telling somebody a door is locked before they walk
/// into it.** Without it the app would offer the coach to everybody and let the
/// server refuse, which is a worse experience than saying so up front and
/// indistinguishable, to a runner, from the app being broken.
///
/// `core.entitlements` is readable by its owner precisely so this can exist:
/// the table grants `select` to `authenticated` under a row-level policy and
/// grants nothing else at all, so a client can see what it bought and cannot
/// write what it did not.
///
/// ## Failure is [CoachAccess.free]
///
/// Every error path resolves to free: no session, no row, a dead network, a
/// timeout, a malformed row. That is the safe direction for a *drawing*
/// decision, and it is safe precisely because it is not the gate — the worst
/// case is a paying runner briefly shown a locked door on a bad connection,
/// which the server would then let through anyway. The reverse default would
/// draw an unlocked door and produce a 402 the moment it was opened.
abstract class EntitlementRepository {
  /// The tier this runner has for the running app, now.
  Future<CoachAccess> access();

  /// The same row, in enough detail to **print**: which tier, and what the
  /// store currently says about the money.
  ///
  /// Separate from [access] because the two questions have different right
  /// answers. A gate wants a boolean and wants it to fail closed. A settings
  /// row wants to distinguish "you are on the free app" from "your payment
  /// failed", which are the same boolean and not the same sentence.
  ///
  /// Implementations must keep [CoachSubscription.isSubscribed] in step with
  /// [access] — same row, same rules, read once.
  Future<CoachSubscription> subscription();
}

/// Reads `core.entitlements` for the signed-in user and this app.
class SupabaseEntitlements implements EntitlementRepository {
  /// `const` so a widget can take one as a default argument. It holds no
  /// state — the Supabase client is resolved per call by [_client] — so a
  /// shared instance and a fresh one behave identically.
  const SupabaseEntitlements({
    SupabaseClient? client,
    this.timeout = const Duration(seconds: 5),
    DateTime Function() now = DateTime.now,
  }) : _explicitClient = client,
       _now = now;

  final SupabaseClient? _explicitClient;

  /// Bounds the read. Nothing here is worth blocking the first paint of a
  /// tracker that works offline.
  final Duration timeout;

  /// The clock an expiry is judged against, injectable like every other `now`
  /// in the app. A function rather than an instant, so a shared `const`
  /// instance reads the time at each call rather than once, at construction.
  final DateTime Function() _now;

  /// Every column [CoachSubscription.fromRow] reads, and no others.
  ///
  /// Named so a test can pin it. A column dropped from this string does not
  /// fail the query — the key is simply absent, which reads as null — and a
  /// null `expires_at` means "no end date", so losing it here would quietly
  /// undo the lapse rule rather than break anything.
  static const String columns = 'product, status, expires_at';

  /// Resolved per call so constructing this does not require Supabase to be
  /// initialised, the same reason `AuthRepository` and `SupabaseUnitSettings`
  /// do it.
  SupabaseClient? get _client {
    if (_explicitClient != null) return _explicitClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CoachAccess> access() async => (await subscription()).isSubscribed
      ? CoachAccess.subscribed
      : CoachAccess.free;

  @override
  Future<CoachSubscription> subscription() async {
    final row = await _row();
    return CoachSubscription.fromRow(row, now: _now());
  }

  /// The one read both answers come from.
  Future<Map<String, dynamic>?> _row() async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    // No account is the common case now that the app opens on a working
    // tracker without one (ADR-0019), and it is not an error.
    if (client == null || userId == null) return null;

    try {
      return await client
          .schema('core')
          .from('entitlements')
          .select(columns)
          .eq('user_id', userId)
          .eq('app', 'run')
          .maybeSingle()
          .timeout(timeout);
    } catch (_) {
      // Every failure path is "no entitlement": no session, a dead network, a
      // timeout, a malformed row. Safe for a drawing decision precisely
      // because this is not the gate.
      return null;
    }
  }

  /// The same three rules the Edge Function applies, in the same directions.
  ///
  /// Only `active` grants anything — `grace` is the tempting mistake, since it
  /// reads like "still fine" and means "the store has not been paid". An
  /// unrecognised product grants nothing rather than the dearest thing, so a
  /// typo or a future SKU cannot unlock a screen it did not buy. And an
  /// `active` row stops granting a day after `expires_at`, the lapse `tierFor`
  /// refuses, so the coach is drawn locked for exactly the rows the server
  /// will turn away.
  ///
  /// **Delegates to [CoachSubscription.fromRow]** rather than restating those
  /// rules. They were written twice for a while — here, and in the type that
  /// prints the same row — and two copies of a money rule is one copy and a
  /// future disagreement.
  static CoachAccess accessFrom(
    Map<String, dynamic>? row, {
    required DateTime now,
  }) => CoachSubscription.fromRow(row, now: now).isSubscribed
      ? CoachAccess.subscribed
      : CoachAccess.free;
}
