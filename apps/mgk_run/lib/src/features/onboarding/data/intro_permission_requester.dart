import 'package:geolocator/geolocator.dart';

import '../../health/data/health_kit_workouts.dart';
import '../../health/domain/workout_source.dart';
import '../domain/intro_permission.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PERMISSION REQUESTS
//
// **Both requests are real.** This block used to say the opposite, at length,
// and kept saying it for the whole of the integration it was waiting for:
// location has gone through geolocator and HealthKit through `health` for some
// time, and the notice claiming neither was wired outlived both.
//
// It is recorded here rather than deleted quietly because the stale version
// was not harmless. It named itself the thing that had to change before
// release, and said in bold that shipping without it was an App Store
// rejection - so anyone who read it concluded the release was blocked on work
// that was already done. A placeholder notice is a claim about the code, and
// it goes stale exactly like any other.
//
//   location   — `Geolocator.checkPermission()` first, then `requestPermission()`
//                only when the answer is `denied`. Reading before asking matters:
//                on an already-decided permission a request is either a no-op or
//                a second dialog depending on platform, and a runner who granted
//                this on a previous install should not be asked again.
//
//   healthKit  — `WorkoutSource.requestAccess()`, backed by `health: 13.2.0`.
//                See the note on that branch for why `true` means less here than
//                it looks like it does.
//
// Both keep the two properties [requestIntroPermission] documents below: never
// throws, never hangs.
// ─────────────────────────────────────────────────────────────────────────────

/// Raises the OS dialog for [permission] and reports whether it was allowed.
///
/// Kept out of the widget so the intro can be driven in a test without a
/// platform — `IntroScreen` takes this as a function and the tests pass their
/// own. Everything here is a platform call and nothing here is copy.
///
/// **Never throws, and never hangs.** Both matter. A permission is the only
/// blocking platform call in onboarding's critical path, and onboarding is the
/// one screen a runner cannot route around, so a plugin that is missing, a
/// channel that is not ready or a call that simply never answers must not be
/// able to strand somebody on their first screen. Anything thrown resolves to
/// "not granted"; anything slower than [_answerDeadline] does too. Both land on
/// the refusal copy, which is a real path the coach already handles rather than
/// an error state.
///
/// **The deadline is a backstop, not a patience limit.** It is far longer than
/// anybody needs to read a system dialog, because a runner taking their time
/// must not be recorded as having refused. If it ever fires, something
/// underneath is broken. Little is lost by being wrong: permissions are
/// re-checked where they are used, so a grant that arrives late is picked up
/// there.
Future<bool> requestIntroPermission(
  IntroPermission permission, {
  WorkoutSource? health,
}) async {
  try {
    return await _request(
      permission,
      health ?? HealthKitWorkouts(),
    ).timeout(_answerDeadline, onTimeout: () => false);
  } catch (_) {
    return false;
  }
}

/// Long enough to read a dialog and think about it; short enough that a broken
/// platform channel does not strand somebody on their first screen.
const Duration _answerDeadline = Duration(seconds: 45);

/// The real dialogs.
///
/// **Asking twice is not a thing that happens.** iOS records the answer the
/// first time and never shows the sheet again for the life of the install, for
/// either of these. That is why location checks before it requests — a second
/// `requestPermission` on an already-decided permission returns the standing
/// answer rather than prompting — and it is why the "run setup again" control
/// in Settings has to explain how to revoke on the phone instead of pretending
/// it can reset anything.
Future<bool> _request(IntroPermission permission, WorkoutSource health) async {
  switch (permission.kind) {
    case IntroPermissionKind.location:
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      // whileInUse is enough to record a run with the app open; `always` is
      // what keeps it going with the screen locked and is asked for separately
      // by iOS, later, on its own schedule.
      return p == LocationPermission.always ||
          p == LocationPermission.whileInUse;

    case IntroPermissionKind.healthKit:
      // **True here means "the sheet was answered", not "reads were allowed".**
      // iOS refuses to tell an app which health reads it got, by design, so
      // there is no better signal available and the coach's reply is written
      // not to over-claim on the strength of it.
      return health.requestAccess();
  }
}
