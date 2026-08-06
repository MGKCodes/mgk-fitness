import 'package:mgk_units/mgk_units.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/unit_preferences.dart';

/// Reads and writes the lifter's units from `core.user_settings`.
///
/// The row is **shared with Run**, so this touches only the two columns it owns
/// and never rewrites the whole row — clobbering `theme` or `default_rest_timer`
/// because we happened to be saving a unit is exactly the class of bug a shared
/// table invites.
///
/// Nothing here throws. Signed out, offline, or no settings row yet all mean
/// "use the default", never an error the lifter should see. Only 5 of 12
/// accounts hold a row at all, so the absent case is the common one.
class SupabaseUnitPreferences implements UnitPreferencesStore {
  SupabaseUnitPreferences({
    SupabaseClient? client,
    this.timeout = const Duration(seconds: 5),
  }) : _explicit = client;

  final SupabaseClient? _explicit;

  /// Bounds the read so a dead network cannot hang a launch on a cosmetic
  /// setting.
  final Duration timeout;

  /// Resolved per call, so constructing this does not require Supabase to be
  /// initialised — the same trick Run's repositories use to stay test-friendly.
  SupabaseClient? get _client {
    if (_explicit != null) return _explicit;
    try {
      return Supabase.instance.client;
    } on Object {
      return null;
    }
  }

  @override
  Future<UnitPreferences> load() async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return const UnitPreferences();
    try {
      final row = await client
          .schema('core')
          .from('user_settings')
          .select('distance_unit, weight_unit')
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(timeout);
      if (row == null) return const UnitPreferences();
      return UnitPreferences(
        distance: UnitSystem.fromStored(row['distance_unit'] as String?),
        mass: MassUnit.fromStored(row['weight_unit'] as String?),
      );
    } on Object {
      return const UnitPreferences();
    }
  }

  @override
  Future<void> save(UnitPreferences prefs) async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return;
    try {
      await client
          .schema('core')
          .from('user_settings')
          .upsert(<String, dynamic>{
            'user_id': userId,
            'distance_unit': prefs.distance.storedValue,
            'weight_unit': prefs.mass.storedValue,
          }, onConflict: 'user_id')
          .timeout(timeout);
    } on Object {
      // The next save or launch reconciles. A unit that did not reach the
      // server is not worth interrupting anybody for.
    }
  }
}
