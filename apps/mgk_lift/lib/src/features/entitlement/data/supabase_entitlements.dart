import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entitlement.dart';

/// Reads `core.entitlements` for this account, in this app.
///
/// The table is client-read-only by design — there is no INSERT, UPDATE or
/// DELETE policy and no such grant to `authenticated` — so this class can only
/// ever ask. Writing is the RevenueCat webhook's job, under `service_role`.
///
/// **Scoped to `app = 'lift'`, and that is load-bearing.** The table is keyed
/// `(user_id, app)` because pricing is per app and never cross-app: a Run
/// subscription must not unlock the coach here. This was nearly got wrong once
/// already — the release plan claimed a suite-wide grant until the column was
/// actually looked at on 2026-09-01.
class SupabaseEntitlements implements EntitlementSource {
  SupabaseEntitlements({
    SupabaseClient? client,
    this.timeout = const Duration(seconds: 5),
  }) : _explicit = client;

  static const String _app = 'lift';

  final SupabaseClient? _explicit;

  /// Bounds the read so a dead network cannot hang a launch. Five seconds
  /// matches `SupabaseUnitPreferences`; the fallback is the cached answer, not
  /// an error, so a slow network costs a stale screen rather than a broken one.
  final Duration timeout;

  /// Resolved per call, so constructing this does not require Supabase to be
  /// initialised and a test can pass an instance in.
  SupabaseClient? get _client {
    if (_explicit != null) return _explicit;
    try {
      return Supabase.instance.client;
    } on Object {
      return null;
    }
  }

  /// What the server says, or null when it cannot say.
  ///
  /// **Null and [Entitlement.none] are different answers and both are
  /// reachable.** No row means this account has never paid — that is
  /// information, and it is [Entitlement.none]. Signed out, timed out or failed
  /// means we do not know, and collapsing that into "has not paid" is what
  /// shows a paywall to a paying customer on a bad connection.
  @override
  Future<Entitlement?> fetch() async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return null;

    try {
      final row = await client
          .schema('core')
          .from('entitlements')
          .select('product, status, expires_at')
          .eq('user_id', userId)
          .eq('app', _app)
          .maybeSingle()
          .timeout(timeout);

      // Reached the server and it has no row for this account. A real answer,
      // and the common one: as of 2026-09-02 the table holds exactly one row.
      if (row == null) return Entitlement.none;

      final expires = row['expires_at'];
      return Entitlement(
        tier: EntitlementTier.parse(row['product'] as String?),
        // A row with no status cannot grant anything, and saying so as a string
        // the switch will not match is more honest than defaulting to 'active'.
        status: (row['status'] as String?) ?? 'unknown',
        expiresAt: expires is String ? DateTime.tryParse(expires) : null,
      );
    } on Object {
      // Every failure is the same failure to a caller: no answer. Deliberately
      // not rethrown — an entitlement read that throws would take down a launch
      // over what the Plan tab renders.
      return null;
    }
  }
}
