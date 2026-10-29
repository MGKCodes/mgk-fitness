import 'package:shared_preferences/shared_preferences.dart';

import '../domain/intro_store.dart';

/// Whether this phone has met the coach's first lines, kept on the phone.
///
/// Same shape as `LocalCoachPreference`: the plugin is resolved per call, so
/// building this does not need the binding to be ready and a test can pass an
/// instance in. A bool under one key, because that is all it is; Run keeps the
/// same fact in a marker file only because Run's also holds a name.
class LocalIntroStore implements IntroStore {
  LocalIntroStore({SharedPreferences? prefs}) : _explicit = prefs;

  static const String _key = 'intro.seen';

  final SharedPreferences? _explicit;

  Future<SharedPreferences?> get _prefs async {
    if (_explicit != null) return _explicit;
    try {
      return await SharedPreferences.getInstance();
    } on Object {
      return null;
    }
  }

  /// False only when the phone can be read and says it has not been seen.
  ///
  /// Anything else answers true: an unreachable plugin, a read that throws, a
  /// value of the wrong type. See [IntroStore] for why a store that cannot be
  /// read must open the app rather than the welcome.
  @override
  Future<bool> hasSeen() async {
    try {
      final prefs = await _prefs;
      if (prefs == null) return true;
      if (!prefs.containsKey(_key)) return false;
      final value = prefs.get(_key);
      return value is bool ? value : true;
    } on Object {
      return true;
    }
  }

  @override
  Future<void> markSeen() async {
    try {
      final prefs = await _prefs;
      await prefs?.setBool(_key, true);
    } on Object {
      // Shown once more next launch, which is the whole cost.
    }
  }
}
