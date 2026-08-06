import 'session.dart';

/// Owns a training session while it is happening.
///
/// **Every method persists before it returns.** That is the contract, not an
/// implementation detail: a session is never held only in memory, so
/// force-quitting the app between two sets loses nothing. It is the same rule
/// `mgk_run` applies to GPS points, for the same reason — the data arrives while
/// the user is doing something else and cannot be asked for again.
///
/// Nothing here touches the network. Sync is a separate concern that runs when
/// there is a connection, and its absence must never block a set being logged.
abstract interface class SessionRecorder {
  /// The session in progress, or null.
  ///
  /// Non-null after a crash if one was interrupted — a workout row with no
  /// `endedAt`. Callers should offer it back rather than silently starting a
  /// second one over the top.
  Future<Session?> current();

  /// Begins a session. Throws [SessionInProgress] if one is already open,
  /// rather than quietly abandoning it.
  Future<Session> start({String? name, DateTime? at});

  /// Adds a movement to the open session.
  Future<Session> addExercise(String name, {String? cardioMode});

  /// Adds a set to a movement, carrying the previous set's numbers forward.
  ///
  /// Carrying forward is the single biggest ergonomic difference between a
  /// tracker people use and one they abandon: the second set of an exercise is
  /// nearly always the same weight and reps as the first, and retyping both
  /// every time is what makes logging feel like admin.
  Future<Session> addSet(String exerciseId);

  /// Edits a set. Any omitted field is left as it was.
  Future<Session> updateSet(
    String setId, {
    int? reps,
    double? weightKg,
    bool? isCompleted,

    /// Marks a set as a warm-up, or back. The Drift recorder always supported
    /// this — the contract did not, so nothing written against the interface
    /// could reach a column the domain reads on every total.
    SetType? setType,
    int? durationS,
    double? distanceM,
  });

  Future<Session> removeSet(String setId);

  Future<Session> removeExercise(String exerciseId);

  /// Ends the session and stamps its duration. Returns the finished session.
  Future<Session> finish({DateTime? at});

  /// Abandons the session, deleting it outright.
  ///
  /// A hard delete rather than a soft one: an abandoned session was never
  /// training that happened, so it should not sync anywhere or appear in a log.
  /// That is different from deleting a *finished* session, which is soft.
  Future<void> discard();
}

/// Thrown when starting a session while one is already open.
class SessionInProgress implements Exception {
  const SessionInProgress();

  @override
  String toString() => 'A session is already in progress.';
}

/// Thrown when an operation needs an open session and there is none.
class NoSessionInProgress implements Exception {
  const NoSessionInProgress();

  @override
  String toString() => 'No session is in progress.';
}
