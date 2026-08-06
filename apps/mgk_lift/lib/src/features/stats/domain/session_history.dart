import '../../tracking/domain/session.dart';

/// The finished sessions, newest first.
///
/// Separate from `SessionRecorder` on purpose: that owns the one session
/// happening now, this reads everything that already happened. Conflating them
/// is how a screen ends up able to mutate history by accident.
abstract interface class SessionHistory {
  Future<List<Session>> all({int? limit});
}

/// A fixed log. What tests and previews want.
class InMemorySessionHistory implements SessionHistory {
  const InMemorySessionHistory([this._sessions = const <Session>[]]);

  final List<Session> _sessions;

  @override
  Future<List<Session>> all({int? limit}) async {
    final sorted = <Session>[..._sessions]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return limit == null ? sorted : sorted.take(limit).toList();
  }
}
