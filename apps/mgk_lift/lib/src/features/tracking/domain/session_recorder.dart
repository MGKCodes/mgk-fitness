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
  ///
  /// **A saved workout is not an open session**, even though it is stored as a
  /// workout row with no `endedAt` too. An implementation that reads only
  /// `endedAt` will hand a lifter one of their own library entries to resume,
  /// and finishing it would turn a routine into a session that never happened.
  /// See `Workouts.isTemplate`.
  Future<Session?> current();

  /// Begins a session. Throws [SessionInProgress] if one is already open,
  /// rather than quietly abandoning it.
  Future<Session> start({String? name, DateTime? at});

  /// Adds a movement to the open session, after the last one.
  ///
  /// Throws [SessionLimitReached] past [SessionLimits.movements].
  Future<Session> addExercise(String name, {String? cardioMode});

  /// Adds several movements at once, in the order given — what the picker
  /// hands back when more than one is chosen. One write, so a session never
  /// holds half of a selection.
  ///
  /// Throws [SessionLimitReached] if the whole selection would not fit, rather
  /// than adding the part that does.
  Future<Session> addExercises(List<String> names);

  /// Fills the open session from a saved workout: its name, its movements in
  /// order **with their sets already laid out**, a back-reference to where
  /// they came from, and [snapshot] — the workout as it stood, which Finish
  /// compares the session against so the workout can learn from it.
  ///
  /// The sets arrive seeded: each movement's count from the workout, reps from
  /// its target or from last time, weight from last time — see `seedSets`.
  /// Nothing is ticked. It used to add bare movement names, so a six-movement
  /// workout opened as six empty cards.
  ///
  /// Takes primitives rather than a `SavedWorkout` so the recorder does not
  /// have to know the library exists. It renames the session on the
  /// assumption that nothing has been logged into it yet.
  ///
  /// Throws [SessionLimitReached] if the movements would not fit.
  Future<Session> fillFromLibrary({
    required String workoutId,
    required String name,
    required List<SeededMovement> movements,
    String? snapshot,
  });

  /// Adds a set to a movement, carrying the previous set's numbers forward.
  ///
  /// Carrying forward is the single biggest ergonomic difference between a
  /// tracker people use and one they abandon: the second set of an exercise is
  /// nearly always the same weight and reps as the first, and retyping both
  /// every time is what makes logging feel like admin.
  ///
  /// [reps] and [weightKg] seed the **first** set, which has nothing in this
  /// session to carry from — the caller passes what the lifter did last time.
  /// Ignored once the movement has a set of its own to copy.
  ///
  /// Throws [SessionLimitReached] past [SessionLimits.setsPerMovement].
  Future<Session> addSet(String exerciseId, {int? reps, double? weightKg});

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

  /// Removes one set. The movement's remaining sets are renumbered in the
  /// same write, so removing set 2 of 3 and adding one reads 1, 2, 3 — not
  /// 1, 3, 3, which is what numbering by count without renumbering produced.
  Future<Session> removeSet(String setId);

  /// Puts back a set [removeSet] took away — the Undo. Same id, same values,
  /// same position; the sets after it move down one.
  Future<Session> restoreSet(String exerciseId, SessionSet set);

  /// Removes a movement and its sets. The remaining movements close the gap in
  /// the same write, so a movement added afterwards lands last rather than
  /// sharing a position with one already there.
  Future<Session> removeExercise(String exerciseId);

  /// Puts back a movement [removeExercise] took away, sets and all, at the
  /// position it held.
  Future<Session> restoreExercise(SessionExercise exercise);

  /// Swaps a movement for another, in its place.
  ///
  /// **Work that happened is never deleted by a swap.** A movement with nothing
  /// ticked is replaced where it stands. One with ticked sets stays — those
  /// sets were lifted — and the replacement goes directly beneath it. The old
  /// behaviour did both things wrong: it deleted the logged sets and put the
  /// replacement at the bottom of the session.
  ///
  /// [sets] rows are seeded on the replacement with [reps] and [weightKg].
  Future<Session> replaceExercise(
    String exerciseId,
    String name, {
    int sets = 0,
    int? reps,
    double? weightKg,
  });

  /// Moves a movement to [toIndex] in the session's order.
  Future<Session> moveExercise(String exerciseId, int toIndex);

  /// Ends the session and stamps its duration. Returns the finished session.
  ///
  /// **Sets that were never ticked are dropped**, and so is any movement left
  /// with nothing. They are sets that did not happen, and keeping them stored
  /// fiction and uploaded it. The Finish sheet lists them first, so nothing
  /// goes without the lifter having seen it. Decision D3 in
  /// `docs/lift-2.0.0-logging-rework.md`.
  Future<Session> finish({DateTime? at});

  /// Abandons the session, deleting it outright.
  ///
  /// A hard delete rather than a soft one: an abandoned session was never
  /// training that happened, so it should not sync anywhere or appear in a log.
  /// That is different from deleting a *finished* session, which is soft.
  Future<void> discard();
}

/// A movement with its sets already laid out — a saved workout as a session
/// opens with it.
typedef SeededMovement = ({
  String name,
  List<({int reps, double weightKg})> sets,
});

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
