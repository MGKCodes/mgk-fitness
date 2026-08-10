import 'health_workout.dart';

/// Where workouts recorded outside this app come from.
///
/// A port, so the training log depends on "workouts from Health" rather than on
/// a plugin — and so the parts worth testing can be tested without a device.
abstract class WorkoutSource {
  /// Puts the Health permission sheet in front of the person.
  ///
  /// **The bool says the request completed, not that anything was granted.**
  /// iOS deliberately refuses to tell an app which read permissions were
  /// allowed, so there is no honest way to return that
  /// (docs/architecture/run-recording.md). Treat `false` as "we could not ask"
  /// — a platform without Health, or a failure — and never as a refusal.
  Future<bool> requestAccess();

  /// Workouts starting at or after [from], deduplicated.
  ///
  /// Empty is the normal answer for a person who declined, a person with no
  /// workouts, and a platform with no Health. Those are not distinguishable
  /// here and the UI must not try.
  Future<List<HealthWorkout>> since(DateTime from);
}

/// Converts a Health distance into metres, or gives up.
///
/// The plugin hands back a number and a unit separately, and the unit is
/// whatever the writing app chose — a watch logging miles is ordinary. Getting
/// this wrong scales every distance in the log by 1.6, which is exactly the
/// kind of fault that looks like a working app until someone reads their own
/// numbers.
///
/// **Returns null rather than guessing.** An unrecognised unit becomes a run
/// with no distance, which the log already renders honestly (principle 7 in
/// docs/design.md) — far better than a plausible wrong number.
double? metresFrom(num? value, String? unitName) {
  if (value == null || unitName == null) return null;
  final double v = value.toDouble();
  // The names are HealthDataUnit's, checked against the enum rather than
  // guessed — there is no KILOMETER member, so a branch for it would have been
  // dead code implying a case that cannot arrive.
  return switch (unitName.toUpperCase()) {
    'METER' => v,
    'CENTIMETER' => v / 100,
    'INCH' => v * 0.0254,
    'FOOT' => v * 0.3048,
    'YARD' => v * 0.9144,
    'MILE' => v * 1609.344,
    _ => null,
  };
}

/// Kilocalories, or nothing.
///
/// Health reports energy in kcal or kJ depending on the writing app, and the
/// difference between them is a factor of 4.184. Same rule as [metresFrom]: an
/// unrecognised unit yields null rather than a confident wrong number.
double? kcalFrom(num? value, String? unitName) {
  if (value == null || unitName == null) return null;
  final double v = value.toDouble();
  // LARGE_CALORIE is the dietary Calorie, i.e. a kilocalorie; SMALL_CALORIE is
  // the thermochemical one, a thousandth of it. Health uses both names for the
  // same pair of quantities, which is precisely why this is a table and not an
  // inline multiplication.
  return switch (unitName.toUpperCase()) {
    'KILOCALORIE' || 'LARGE_CALORIE' => v,
    'SMALL_CALORIE' => v / 1000,
    'JOULE' => v / 4184,
    _ => null,
  };
}
