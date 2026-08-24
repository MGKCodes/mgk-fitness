import 'package:meta/meta.dart';

/// A workout the lifter has saved: a name, and the movements it contains.
///
/// **This is the user-facing list, and it is not [WorkoutTemplate].** The two
/// were collapsed into one thing when Liftio was ported and the app has been
/// short a whole concept since:
///
///   * `workoutTemplates` — the fifteen ready-made sessions and eight splits
///     the app ships with. They are the coach's raw material. Nothing starts a
///     session from one; you *add* one to your library, and what you get is a
///     copy that is yours to rename, edit and delete.
///   * a [SavedWorkout] — a row in the lifter's own library, however it got
///     there: added from a premade, built by hand, or saved off the back of a
///     session they just did. **This** is what a session is started from.
///
/// So the Knowledge decision *"Lift templates are the coach's grounding layer,
/// not a user-facing library"* is upheld rather than reversed. The app-provided
/// list stays the coach's; the surface a lifter browses is their own work.
@immutable
class SavedWorkout {
  const SavedWorkout({
    required this.id,
    required this.name,
    required this.movements,
    required this.savedAt,
    this.premadeId,
  });

  /// Shared with the workout row it is stored as, and with the Supabase row if
  /// it ever goes up.
  final String id;

  final String name;

  /// Movement names, in the order they should be done.
  ///
  /// **Names and nothing else — no sets, no weights.** A saved workout says
  /// what to do, not what to lift, which is the rule the template shortcut it
  /// replaces already followed. Carrying numbers would be the app asserting
  /// something only the lifter knows, and it would go stale the moment they got
  /// stronger. The number a lifter actually wants mid-set is what they did on
  /// this movement *last time*, and `PreviousPerformance` already puts that on
  /// the exercise card at the point of use — so nothing is lost by leaving it
  /// out of here.
  final List<String> movements;

  /// When it was saved. The library is ordered newest first on this, so a
  /// workout somebody has just added is where they look for it.
  final DateTime savedAt;

  /// The premade this was added from, or null if it was built by hand or saved
  /// from a session.
  ///
  /// Only ever a back-reference. The copy is independent from the moment it is
  /// made: editing one of the fifteen does not reach into a library, and
  /// deleting a saved workout does not remove anything from the fifteen. What
  /// this buys is the browser being able to say which ones you already have.
  final String? premadeId;

  int get movementCount => movements.length;
}

/// The lifter's saved workouts.
///
/// Separate from `SessionRecorder` and `SessionHistory` for the same reason
/// those two are separate from each other: this owns routines that were never
/// performed, the recorder owns the one session happening now, and the history
/// owns everything that already happened. All three are stored as workout rows
/// and the three readers must never see each other's — a template turning up as
/// "the session you were in the middle of" is the specific bug the split
/// prevents.
abstract interface class WorkoutLibrary {
  /// Every saved workout, newest first.
  Future<List<SavedWorkout>> all();

  /// Writes a workout to the library.
  ///
  /// **One write path for all three ways in**, because all three reduce to the
  /// same two things: a name and an ordered list of movement names. Saving a
  /// finished session takes them off the session, adding a premade takes them
  /// off the premade, and building one by hand collects them a movement at a
  /// time. Three methods here would have been three chances to write a
  /// half-formed row.
  Future<SavedWorkout> save({
    required String name,
    required List<String> movements,
    String? fromPremade,
  });

  /// Deletes a saved workout.
  Future<void> remove(String id);
}

/// A name that is not already taken, suffixed `(2)`, `(3)` … if it is.
///
/// Liftio's rule, and worth keeping. Duplicates are *allowed* — re-adding Push
/// so you can keep a heavy and a light version of it is a real thing people do,
/// and blocking it would be the app deciding it knows better. What is not
/// useful is two rows both called `Push` in a list you have to choose from
/// standing at a rack, so the second one says which one it is.
///
/// Applied when adding a premade or a whole split, where the name comes from
/// the app. A name the lifter typed themselves is left exactly as they typed
/// it — silently renaming something somebody has just written is worse than
/// letting them have two of them.
String uniqueWorkoutName(String wanted, Iterable<String> taken) {
  final existing = taken.toSet();
  if (!existing.contains(wanted)) return wanted;
  var suffix = 2;
  while (existing.contains('$wanted ($suffix)')) {
    suffix++;
  }
  return '$wanted ($suffix)';
}

/// A library held in memory. What tests and previews want.
///
/// Mirrors the Drift implementation's ordering rather than the insertion order,
/// so a test that passes here is testing the same list a lifter sees.
class InMemoryWorkoutLibrary implements WorkoutLibrary {
  InMemoryWorkoutLibrary([
    Iterable<SavedWorkout> initial = const <SavedWorkout>[],
  ]) : _saved = <SavedWorkout>[...initial];

  final List<SavedWorkout> _saved;
  int _ids = 0;

  @override
  Future<List<SavedWorkout>> all() async =>
      <SavedWorkout>[..._saved]..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  @override
  Future<SavedWorkout> save({
    required String name,
    required List<String> movements,
    String? fromPremade,
  }) async {
    final workout = SavedWorkout(
      id: 'saved-${++_ids}',
      name: name,
      movements: <String>[...movements],
      // Nudged apart, so two saves in the same tick still order newest-first.
      // The Drift store has the same problem for a different reason — it keeps
      // a `DateTime` to the second — and solves it with `rowid`. Both end up
      // ordering by insertion, which is what a lifter reads "newest" as.
      savedAt: DateTime.now().add(Duration(microseconds: _ids)),
      premadeId: fromPremade,
    );
    _saved.add(workout);
    return workout;
  }

  @override
  Future<void> remove(String id) async =>
      _saved.removeWhere((SavedWorkout w) => w.id == id);
}
