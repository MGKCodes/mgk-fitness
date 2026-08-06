import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/units/unit_system.dart';
import '../domain/unit_preference.dart';
import '../domain/unit_settings.dart';
import 'unit_cache.dart';
import 'unit_cache_factory.dart';

/// The runner's display unit, backed by the **shared**
/// `public.user_settings.distance_unit` column and cached on device.
///
/// The column is shared with Liftio (ADR-0008), so changing units in one app
/// changes them in the other — which is the point of one account across the
/// platform, and why this is not a Runio-local preference.
///
/// Reads prefer the cache. A display unit is not worth blocking first paint on
/// the network, and a runner who chose miles should not see kilometres for a
/// moment on every cold launch. The server is re-read in the background so a
/// change made in Liftio lands on the next launch.
class SupabaseUnitSettings implements UnitSettings {
  SupabaseUnitSettings({
    SupabaseClient? client,
    UnitCache? cache,
    this.remoteTimeout = const Duration(seconds: 5),
  }) : _explicitClient = client,
       _cache = cache ?? createUnitCache();

  final SupabaseClient? _explicitClient;
  final UnitCache _cache;

  /// Bounds the first-launch read, where there is no cache to fall back on, so
  /// a dead network cannot hang the app on a cosmetic setting.
  final Duration remoteTimeout;

  /// Resolved per call, so constructing this does not require Supabase to be
  /// initialised (the same reason [AuthRepository] does it).
  SupabaseClient? get _client {
    if (_explicitClient != null) return _explicitClient;
    try {
      return Supabase.instance.client;
    } on Object {
      return null;
    }
  }

  @override
  Future<UnitSystem> load() async {
    final cached = await _cache.read();
    if (cached != null) {
      // Don't wait: this launch already has an answer good enough to paint.
      unawaited(_refreshCache());
      return cached;
    }
    final remote = await _fetch();
    if (remote != null) await _cache.write(remote);
    return remote ?? UnitSystem.metric;
  }

  @override
  Future<void> save(UnitSystem unit) async {
    // Local first: the choice takes effect on this device even with no network,
    // and the UI never has to wait on a round trip to reflect a tap.
    await _cache.write(unit);
    await _push(unit);
  }

  Future<void> _refreshCache() async {
    final remote = await _fetch();
    if (remote != null) await _cache.write(remote);
  }

  /// The stored unit, or null if it cannot be read for any reason — signed out,
  /// offline, no settings row yet. All of those mean "use the default", never
  /// an error the runner should see.
  Future<UnitSystem?> _fetch() async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return null;
    try {
      final row = await client
          .schema('core')
          .from('user_settings')
          .select('distance_unit')
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(remoteTimeout);
      if (row == null) return null;
      final value = row['distance_unit'];
      // A row that exists with a null unit means "never chosen" — not metric by
      // assertion, so let the caller fall through to its own default.
      if (value == null) return null;
      return UnitPreference.fromStored(value);
    } on Object {
      return null;
    }
  }

  /// Best-effort write. Upserts because Runio may be the first app to create the
  /// row, and touches **only** `distance_unit` so Liftio's own columns in this
  /// shared row are never overwritten.
  Future<void> _push(UnitSystem unit) async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return;
    try {
      await client
          .schema('core')
          .from('user_settings')
          .upsert(<String, dynamic>{
            'user_id': userId,
            'distance_unit': unit.storedValue,
          }, onConflict: 'user_id')
          .timeout(remoteTimeout);
    } on Object {
      // The cache already holds the choice; the next save or launch reconciles.
    }
  }
}
