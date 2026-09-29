import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/rest_lengths.dart';

/// [RestLengths] on the device, as one JSON map of seconds.
///
/// Device-local like the units preference, and not synced: it is a habit of
/// this lifter at this rack rather than a record of anything, and losing it
/// on a new phone costs one −30s tap per movement.
class LocalRestLengths implements RestLengths {
  static const String _key = 'rest_lengths.v1';

  /// Past a certain count the map is a list of every movement ever done, not
  /// a set of habits. Oldest entries are not tracked, so the cap simply stops
  /// learning new ones rather than evicting — a lifter with two hundred
  /// movements has bigger problems than a rest default.
  static const int _cap = 200;

  @override
  Future<Map<String, Duration>> all() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return <String, Duration>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, Duration>{};
      return <String, Duration>{
        for (final entry in decoded.entries)
          if (entry.value is int)
            entry.key: Duration(seconds: entry.value as int),
      };
    } on Object {
      // A corrupt preference costs the defaults, never the session.
      return <String, Duration>{};
    }
  }

  @override
  Future<void> remember(String movement, Duration length) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await all();
      final key = movement.toLowerCase();
      if (!current.containsKey(key) && current.length >= _cap) return;
      current[key] = length;
      await prefs.setString(
        _key,
        jsonEncode(<String, int>{
          for (final e in current.entries) e.key: e.value.inSeconds,
        }),
      );
    } on Object {
      // Remembering is a convenience; failing to is not worth a word.
    }
  }
}
