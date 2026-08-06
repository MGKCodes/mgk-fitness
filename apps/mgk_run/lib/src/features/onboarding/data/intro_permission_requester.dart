import '../domain/intro_permission.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PERMISSION REQUESTS — PLACEHOLDER
//
// **Neither request below is real.** Both return "granted" without asking the
// OS anything, so the onboarding conversation can be walked end to end while it
// is being designed.
//
// This is the one file that has to change when the platform work lands. What
// replaces each branch:
//
//   location   — geolocator, which is already a dependency and already used by
//                `recording/data/geolocator_location_source.dart`:
//
//                  var p = await Geolocator.checkPermission();
//                  if (p == LocationPermission.denied) {
//                    p = await Geolocator.requestPermission();
//                  }
//                  return p == LocationPermission.always ||
//                      p == LocationPermission.whileInUse;
//
//                Read the current state before asking: `requestPermission` on
//                an already-decided permission is either a no-op or a second
//                dialog depending on platform, and a runner who granted this on
//                a previous install should not be asked again.
//
//   healthKit  — in development, nothing landed yet. Needs a package in
//                `pubspec.yaml`, the HealthKit capability in Xcode, and the
//                read types declared. See `docs/roadmap.md`.
//
//                **It has to be wired before release**, not because the
//                conversation is wrong but because asking for authorisation to
//                data the app never reads is an App Store rejection. The step
//                is written and waiting for the integration; it must not
//                overtake it.
//
// Whatever replaces these must keep the two properties [requestIntroPermission]
// documents below: never throws, never hangs.
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
Future<bool> requestIntroPermission(IntroPermission permission) async {
  try {
    return await _placeholder(
      permission,
    ).timeout(_answerDeadline, onTimeout: () => false);
  } catch (_) {
    return false;
  }
}

/// Long enough to read a dialog and think about it; short enough that a broken
/// platform channel does not strand somebody on their first screen.
const Duration _answerDeadline = Duration(seconds: 45);

/// Stands in for the real dialogs. See the PLACEHOLDER block above.
///
/// Grants everything, because the point of the stub is to let the *granted*
/// path be walked; the refusal path is exercised by the widget tests, which
/// inject their own answer rather than calling this at all.
Future<bool> _placeholder(IntroPermission permission) async {
  switch (permission.kind) {
    case IntroPermissionKind.location:
    case IntroPermissionKind.healthKit:
      return true;
  }
}
