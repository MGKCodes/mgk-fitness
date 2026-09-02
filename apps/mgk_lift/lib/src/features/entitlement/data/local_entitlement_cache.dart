import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entitlement.dart';

/// The last entitlement answer this device was given.
///
/// Same shape as [LocalCoachPreference] and for the same reason: the plugin is
/// resolved per call rather than at construction, so building this needs no
/// binding and a test can pass an instance in.
///
/// **Presentation only, and safe because of it.** This decides whether the app
/// shows the paid half while the server cannot be reached. It grants nothing:
/// the coach Edge Function re-reads `core.entitlements` under `service_role`
/// before spending anything, so a device holding a stale `true` gets a nicer
/// screen and a refusal from the server, which is the right way round.
class LocalEntitlementCache implements EntitlementCache {
  LocalEntitlementCache({SharedPreferences? prefs}) : _explicit = prefs;

  /// Namespaced by app rather than bare, because `core.entitlements` is keyed
  /// per app and Run will want the same trick. A key called `entitled` would
  /// have been the suite-wide assumption this table already caught us making
  /// once.
  static const String _key = 'entitlement.lift.paid';

  final SharedPreferences? _explicit;

  Future<SharedPreferences?> get _prefs async {
    if (_explicit != null) return _explicit;
    try {
      return await SharedPreferences.getInstance();
    } on Object {
      return null;
    }
  }

  /// Null when this device has never been told, which is not the same as false
  /// and is why the whole interface is nullable.
  @override
  Future<bool?> lastKnownPaid() async {
    final prefs = await _prefs;
    return prefs?.getBool(_key);
  }

  @override
  Future<void> remember({required bool paid}) async {
    final prefs = await _prefs;
    await prefs?.setBool(_key, paid);
  }

  /// Removed rather than set to false, so "never been told" survives a
  /// sign-out. Writing false would claim this device knows the next person has
  /// not paid, which it does not.
  @override
  Future<void> forget() async {
    final prefs = await _prefs;
    await prefs?.remove(_key);
  }
}
