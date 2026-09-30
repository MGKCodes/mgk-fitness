import 'package:shared_preferences/shared_preferences.dart';

import '../domain/coach_preference.dart';

/// The coach switch, on this device.
///
/// Same shape as [LocalUnitPreferences] and for one of the same reasons — the
/// plugin is resolved per call rather than at construction, so building this
/// does not require the binding to be ready and a test can pass an instance in.
///
/// It does **not** have a remote half, and that is the design rather than an
/// omission: see [CoachPreferenceStore] for why consent stays on the device.
class LocalCoachPreference implements CoachPreferenceStore {
  LocalCoachPreference({SharedPreferences? prefs}) : _explicit = prefs;

  static const String _key = 'coach.enabled';

  final SharedPreferences? _explicit;

  Future<SharedPreferences?> get _prefs async {
    if (_explicit != null) return _explicit;
    try {
      return await SharedPreferences.getInstance();
    } on Object {
      return null;
    }
  }

  /// True when this device has never been told otherwise.
  ///
  /// An unreachable plugin answers the default rather than throwing, for the
  /// reason on [CoachPreferenceStore]: a launch is not worth failing over a
  /// switch, and the disclosure is on the coach screen regardless of what this
  /// returns.
  @override
  Future<bool> load() async {
    final prefs = await _prefs;
    return prefs?.getBool(_key) ?? true;
  }

  @override
  Future<void> save({required bool enabled}) async {
    final prefs = await _prefs;
    await prefs?.setBool(_key, enabled);
  }
}
