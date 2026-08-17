import 'package:mgk_units/mgk_units.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/unit_preferences.dart';

/// The lifter's units, on this device.
///
/// The device half of [UnitPreferencesStore]: it answers instantly, works with
/// no account, and works with no network. That matters more here than it looks,
/// because **tracking is free and needs no sign-in** — a lifter who never makes
/// an account is not an edge case, and cloud-only storage would mean their unit
/// choice never survived a launch.
///
/// Stored with the same `storedValue` vocabulary `core.user_settings` uses
/// (`km`/`mi`, `kg`/`lbs`) rather than an index or an enum name. One encoding
/// for both sides means a value read from either can be written to the other
/// without a translation table that could disagree with itself.
class LocalUnitPreferences
    implements UnitPreferencesStore, UnitPreferencesSource {
  LocalUnitPreferences({SharedPreferences? prefs}) : _explicit = prefs;

  static const String _distanceKey = 'units.distance';
  static const String _massKey = 'units.mass';

  final SharedPreferences? _explicit;

  /// Resolved per call so constructing this does not require the plugin to be
  /// ready — the same reason [SupabaseUnitPreferences] resolves its client
  /// lazily, and what lets a test pass an instance in.
  Future<SharedPreferences?> get _prefs async {
    if (_explicit != null) return _explicit;
    try {
      return await SharedPreferences.getInstance();
    } on Object {
      return null;
    }
  }

  /// What this device has stored, or null when it has never been told.
  ///
  /// Null is not the default — it is "no answer", which is the distinction that
  /// lets a caller tell a stored preference for kilograms apart from never
  /// having been asked. Returning the default here would make the two
  /// indistinguishable and silently overwrite a cloud value with it.
  @override
  Future<UnitPreferences?> fetch() async {
    final prefs = await _prefs;
    if (prefs == null) return null;
    final distance = prefs.getString(_distanceKey);
    final mass = prefs.getString(_massKey);
    if (distance == null && mass == null) return null;
    return UnitPreferences(
      distance: UnitSystem.fromStored(distance),
      mass: MassUnit.fromStored(mass),
    );
  }

  @override
  Future<void> save(UnitPreferences prefs) async {
    final store = await _prefs;
    if (store == null) return;
    await store.setString(_distanceKey, prefs.distance.storedValue);
    await store.setString(_massKey, prefs.mass.storedValue);
  }

  @override
  Future<UnitPreferences> load() async =>
      await fetch() ?? const UnitPreferences();
}
