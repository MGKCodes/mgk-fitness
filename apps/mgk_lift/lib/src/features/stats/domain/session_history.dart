import '../../tracking/domain/session.dart';

/// The finished sessions, newest first.
///
/// Separate from `SessionRecorder` on purpose: that owns the one session
/// happening now, this reads everything that already happened. Conflating them
/// is how a screen ends up able to mutate history by accident.
abstract interface class SessionHistory {
  Future<List<Session>> all({int? limit});

  /// Deletes a session that happened — **softly**, so the delete goes up as a
  /// tombstone and reaches the lifter's other devices instead of the session
  /// coming back down on the next pull. It leaves the log at once; every total
  /// and best, being a fold over the log, follows.
  Future<void> remove(String id);

  /// Puts back a session [remove] took away — the Undo.
  Future<void> restore(String id);
}

/// A log in memory. What tests and previews want.
class InMemorySessionHistory implements SessionHistory {
  InMemorySessionHistory([Iterable<Session> sessions = const <Session>[]])
    : _sessions = <Session>[...sessions];

  final List<Session> _sessions;
  final Map<String, Session> _removed = <String, Session>{};

  @override
  Future<List<Session>> all({int? limit}) async {
    final sorted = <Session>[..._sessions]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return limit == null ? sorted : sorted.take(limit).toList();
  }

  @override
  Future<void> remove(String id) async {
    final at = _sessions.indexWhere((s) => s.id == id);
    if (at >= 0) _removed[id] = _sessions.removeAt(at);
  }

  @override
  Future<void> restore(String id) async {
    final back = _removed.remove(id);
    if (back != null) _sessions.add(back);
  }
}
