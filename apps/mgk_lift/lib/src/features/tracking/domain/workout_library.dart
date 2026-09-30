import 'dart:async';

import 'package:meta/meta.dart';

import 'template_movement.dart';

export 'template_movement.dart';

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

  /// Shared with the workout row it is stored as, and with the Supabase row
  /// once it goes up.
  final String id;

  final String name;

  /// What to do, in order — each movement with its set count and rep target.
  /// See [TemplateMovement] for why there is never a weight here.
  final List<TemplateMovement> movements;

  /// When it was saved. The library is ordered newest first on this, so a
  /// workout somebody has just added is where they look for it.
  final DateTime savedAt;

  /// The premade this was added from, or null if it was built by hand or saved
  /// from a session. Only ever a back-reference: the copy is independent from
  /// the moment it is made. What this buys is the browser being able to say
  /// which ones you already have.
  final String? premadeId;

  int get movementCount => movements.length;

  /// Working sets across the whole workout — `6 movements · 18 sets`.
  int get setCount => movements.fold(0, (sum, m) => sum + m.sets);

  List<String> get movementNames => <String>[for (final m in movements) m.name];

  SavedWorkout copyWith({String? name, List<TemplateMovement>? movements}) =>
      SavedWorkout(
        id: id,
        name: name ?? this.name,
        movements: movements ?? this.movements,
        savedAt: savedAt,
        premadeId: premadeId,
      );
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

  /// One saved workout, or null if it no longer exists — deleted here, or on
  /// another device and pulled down since.
  Future<SavedWorkout?> byId(String id);

  /// Writes a new workout to the library.
  ///
  /// **One write path for every way in**: saving a finished session, adding a
  /// premade, building one by hand. Each reduces to a name and an ordered list
  /// of movements.
  Future<SavedWorkout> save({
    required String name,
    required List<TemplateMovement> movements,
    String? fromPremade,
  });

  /// Replaces a workout's name and movements, keeping its id and its place.
  ///
  /// The editor's save, and the session's lesson — a template learning from
  /// the session that ran it (see [MovementChange]) is this call.
  Future<SavedWorkout> update(SavedWorkout workout);

  /// Deletes a saved workout. Sessions done from it stay in the log.
  Future<void> remove(String id);

  /// Puts back a workout [remove] took away — the Undo.
  Future<void> restore(String id);

  /// Fires after this library changes — a save, an edit, a delete or its
  /// undo — so a surface showing the list can read it again.
  ///
  /// **Track's row went stale without it.** Track re-read the library when
  /// the session screen returned, but Finish *replaces* that screen with the
  /// summary, so the return came before the summary taught the workout — and
  /// Track said "4 movements" about a workout that now had three.
  Stream<void> get changes;
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
  final Map<String, SavedWorkout> _removed = <String, SavedWorkout>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _ids = 0;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<SavedWorkout>> all() async =>
      <SavedWorkout>[..._saved]..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  @override
  Future<SavedWorkout?> byId(String id) async {
    for (final w in _saved) {
      if (w.id == id) return w;
    }
    return null;
  }

  @override
  Future<SavedWorkout> save({
    required String name,
    required List<TemplateMovement> movements,
    String? fromPremade,
  }) async {
    final workout = SavedWorkout(
      id: 'saved-${++_ids}',
      name: name,
      movements: <TemplateMovement>[...movements],
      // Nudged apart, so two saves in the same tick still order newest-first.
      savedAt: DateTime.now().add(Duration(microseconds: _ids)),
      premadeId: fromPremade,
    );
    _saved.add(workout);
    _changes.add(null);
    return workout;
  }

  @override
  Future<SavedWorkout> update(SavedWorkout workout) async {
    final at = _saved.indexWhere((w) => w.id == workout.id);
    if (at >= 0) _saved[at] = workout;
    _changes.add(null);
    return workout;
  }

  @override
  Future<void> remove(String id) async {
    final at = _saved.indexWhere((w) => w.id == id);
    if (at >= 0) _removed[id] = _saved.removeAt(at);
    _changes.add(null);
  }

  @override
  Future<void> restore(String id) async {
    final back = _removed.remove(id);
    if (back != null) _saved.add(back);
    _changes.add(null);
  }
}
