import 'package:shared_preferences/shared_preferences.dart';

import '../domain/moved_day.dart';

/// [MovedDayStore] on this device: the day, and the date it was chosen for.
///
/// Same shape as `LocalCoachPreference`: the plugin is resolved per call, and
/// an unreachable one answers "nothing moved" rather than failing a launch.
class LocalMovedDay implements MovedDayStore {
  LocalMovedDay({SharedPreferences? prefs}) : _explicit = prefs;

  static const String _dayKey = 'plan.moved.day';
  static const String _onKey = 'plan.moved.on';

  final SharedPreferences? _explicit;

  Future<SharedPreferences?> get _prefs async {
    if (_explicit != null) return _explicit;
    try {
      return await SharedPreferences.getInstance();
    } on Object {
      return null;
    }
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<String?> read(DateTime today) async {
    try {
      final prefs = await _prefs;
      if (prefs == null) return null;
      // Chosen for another day: gone, as the day it was for is.
      if (prefs.getString(_onKey) != _date(today)) return null;
      return prefs.getString(_dayKey);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String day, DateTime today) async {
    try {
      final prefs = await _prefs;
      await prefs?.setString(_dayKey, day);
      await prefs?.setString(_onKey, _date(today));
    } on Object {
      // Nothing to recover: the lifter can choose it again.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final prefs = await _prefs;
      await prefs?.remove(_dayKey);
      await prefs?.remove(_onKey);
    } on Object {
      // A stale choice expires with its day regardless.
    }
  }
}
