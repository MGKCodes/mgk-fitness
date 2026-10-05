import 'package:shared_preferences/shared_preferences.dart';

import '../domain/disclaimer_store.dart';

/// The medical disclaimer's acknowledgement, on this device.
///
/// Same shape as `LocalCoachPreference`: the plugin is resolved per call, so
/// building this does not need the binding ready, and a test can pass its own.
class LocalDisclaimerStore implements DisclaimerStore {
  LocalDisclaimerStore({SharedPreferences? prefs}) : _explicit = prefs;

  static const String _key = 'legal.medical_disclaimer.acknowledged';

  final SharedPreferences? _explicit;

  Future<SharedPreferences?> get _prefs async {
    if (_explicit != null) return _explicit;
    try {
      return await SharedPreferences.getInstance();
    } on Object {
      return null;
    }
  }

  /// False when it cannot be read: the disclaimer is shown again rather than
  /// skipped.
  @override
  Future<bool> isAcknowledged() async {
    try {
      final prefs = await _prefs;
      return prefs?.getBool(_key) ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> acknowledge() async {
    try {
      final prefs = await _prefs;
      await prefs?.setBool(_key, true);
    } on Object {
      // Deliberate: a failed write only means the lifter is asked again.
    }
  }
}
