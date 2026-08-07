import '../../tracking/domain/session.dart';
import '../../tracking/domain/session_recorder.dart';
import 'plan.dart';
import 'plan_validator.dart';

/// Turns a planned session into a live one.
///
/// **This is where a plan stops being a document.** A template adds movements
/// and stops; a planned session adds the movements AND their sets, with the
/// weight already in, because the coach worked that weight out from what this
/// lifter has actually lifted.
///
/// ## The rule this changes
///
/// `active_session_screen.dart` used to say, of templates:
///
///     A template says what to do, not what to lift, and pre-filling weights
///     would be the app asserting something only the lifter knows.
///
/// That reasoning is right and it is still right — **for a template**, which is
/// a fixed list written for nobody in particular. It stops holding for a plan,
/// because the number did not come from the app asserting anything. It came
/// from their own logged sets, by way of an estimated 1RM and a percentage the
/// coach chose. `PlanValidator` is what makes that true rather than a claim: a
/// weight it could not derive is left null, and a null weight is pre-filled as
/// a blank exactly the way a template's would be.
///
/// So both rules hold at once, which is why this lives here rather than as a
/// flag on the template path.
class SessionFromPlan {
  const SessionFromPlan(this.recorder);

  final SessionRecorder recorder;

  /// Opens a session for [planned] and fills it in.
  ///
  /// Sets are added ticked-OFF: the lifter still does the work and still
  /// confirms each one. Pre-ticking would log a session nobody had done, which
  /// is the one thing a tracker must never do.
  Future<Session> start(PlanSession planned, {DateTime? at}) async {
    var session = await recorder.start(name: planned.title, at: at);

    for (final movement in planned.movements) {
      session = await recorder.addExercise(movement.name);
      final exercise = session.exercises.last;

      for (var i = 0; i < movement.sets; i++) {
        // The first set exists already — `addExercise` seeds one, the way it
        // does for a movement added by hand.
        final target = i < exercise.sets.length
            ? exercise.sets[i]
            : (session = await recorder.addSet(exercise.id)).exercises
                  .firstWhere((SessionExercise e) => e.id == exercise.id)
                  .sets
                  .last;

        session = await recorder.updateSet(
          target.id,
          reps: movement.reps,
          // Null leaves it blank rather than writing a zero. A movement the
          // coach could not put a number on is a real prescription — "leave
          // two in the tank" — and a 0 kg in the field would read as a bug.
          weightKg: movement.target?.kilograms,
        );
      }
    }

    return session;
  }
}

/// The movements of a planned session, after a mid-session swap.
///
/// Pure so the substitution can be tested without a recorder: it is a list
/// operation, and getting it wrong silently replaces the wrong movement.
List<PlannedMovement> applySwap(
  List<PlannedMovement> movements, {
  required String replaces,
  required PlannedMovement with_,
}) => <PlannedMovement>[
  for (final movement in movements)
    if (_sameMovement(movement.name, replaces)) with_ else movement,
];

/// Names are compared loosely because the coach is told the movement's name and
/// hands it back, and a round trip through a model is not case-preserving.
bool _sameMovement(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();
