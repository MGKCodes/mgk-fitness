import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:mgk_run/src/features/health/data/health_read_types.dart';

/// **A Health type left out of the permission request has no symptom.**
///
/// iOS grants read access per type, once, at the moment the sheet is shown, and
/// then never mentions it again — a type that was never asked for is not an
/// error, it is a query that returns nothing for the life of the install. That
/// is indistinguishable from a runner who declined and from a phone with no
/// data (CLAUDE.md rule 6), so nothing on any screen would ever look wrong.
/// These are the assertions that stand in for the symptom.
void main() {
  test('every type the app reads is a type the app asks permission for', () {
    // Workouts, imported into the log from a watch or another app.
    expect(kHealthReadTypes, contains(HealthDataType.WORKOUT));
    // Steps, read over a finished run's window — the figure Strava had for the
    // 23 Aug 10 km (8,468) and this app had no way to produce, because a GPS
    // trace cannot count them.
    expect(kHealthReadTypes, contains(HealthDataType.STEPS));
  });

  test('the request is read-only and matches the types one for one', () {
    // The plugin throws ArgumentError when the two lists differ in length, so
    // a type added to one and forgotten in the other turns the app's only
    // Health permission moment into a crash during onboarding.
    expect(kHealthReadAccess, hasLength(kHealthReadTypes.length));
    expect(
      kHealthReadAccess.every((a) => a == HealthDataAccess.READ),
      isTrue,
      reason: 'this app reads Health and never writes to it',
    );
  });

  test('nothing is requested that no screen shows', () {
    // The sheet a runner is shown is a product surface, not a convenience. The
    // rule is that a type earns its place by appearing somewhere; heart rate,
    // energy and flights climbed are all readable and all deliberately absent
    // until something draws them (see the Phase 2 audit).
    expect(kHealthReadTypes, hasLength(2));
  });
}
