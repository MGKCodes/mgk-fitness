/// How long this lifter rests after each movement, remembered across sessions.
///
/// A heavy squat and a cable fly do not want the same rest, and every app
/// worth comparing against keeps a rest length per exercise (research,
/// 2026-09-29). Lift kept one for the whole session, forgot it at Finish, and
/// started every session at ninety seconds.
///
/// Learned rather than configured: whatever the lifter settles on with −30s
/// and +30s after a movement's set is what that movement's next rest starts
/// at. There is no settings screen for it because the dock already is one.
///
/// Keyed by lowercased movement name, the same key "last time" uses, so a
/// typed movement and a catalogue one are treated alike.
abstract interface class RestLengths {
  /// Every remembered length. Read once, when a session opens.
  Future<Map<String, Duration>> all();

  /// Remembers [length] for [movement].
  Future<void> remember(String movement, Duration length);
}

/// [RestLengths] in memory, for tests and the preview.
class InMemoryRestLengths implements RestLengths {
  InMemoryRestLengths([Map<String, Duration>? seed])
    : _lengths = <String, Duration>{...?seed};

  final Map<String, Duration> _lengths;

  @override
  Future<Map<String, Duration>> all() async => Map.of(_lengths);

  @override
  Future<void> remember(String movement, Duration length) async =>
      _lengths[movement.toLowerCase()] = length;
}
