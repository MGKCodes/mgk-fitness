import 'dart:math' as math;

import '../../../core/units/distance.dart';
import '../../../core/units/unit_system.dart';
import 'training_plan.dart';

/// A prescribed distance is a **round number**, and a run near it counts.
///
/// Two halves of one idea. A plan that says "run 6.8 km" is claiming a precision
/// it does not have: the number came from a weekly volume split by a share
/// table, and no coach on earth would say it out loud. Worse, it invites the
/// runner to chase it — to stand in the road at 6.74 km deciding whether to keep
/// going — which is the same mistake as prescribing a pace to the second.
///
/// So the plan rounds, and then accepts a range around what it asked for.

/// Prescribed distances are stored on a whole-kilometre grid, never below one.
///
/// This is the *stored* rounding, and it exists so the plan's own arithmetic
/// stays clean: the long run cannot tie with a Tuesday, and the arc and the
/// week cannot disagree about the same session. What the runner **reads** is
/// rounded again, in their own unit — see [prescribedValue].
double roundPrescribed(double meters) {
  if (meters <= 0) return 0;
  return math.max(1000, (meters / 1000).round() * 1000).toDouble();
}

/// The prescription as the runner reads it: a whole number in **their** unit.
///
/// A miles runner is told "4 mi", not "4.3 mi". The point of rounding is ease of
/// use, and a number that is round in a unit the runner does not think in is not
/// round to them.
///
/// **Rounded at display, not at generation.** The stored plan stays exact metric
/// so that switching units in Settings re-reads the same plan rather than
/// rewriting it — a toggle must never mutate someone's training. It also means
/// two runners on the same plan are on the same plan; only the sentence they are
/// shown differs.
double prescribedValue(double meters, UnitSystem unit) {
  if (meters <= 0) return 0;
  final raw = unit.isMetric
      ? Distance.meters(meters).kilometers
      : Distance.meters(meters).miles;
  return math.max(1, raw.round()).toDouble();
}

/// The metric distance a runner following [prescribedValue] actually covers.
///
/// Not the same as the stored number: told "4 mi" for a stored 7 km session,
/// they run 6.44 km. Everything that judges whether a session was done has to
/// judge against **what they were told**, not against a number they never saw.
double prescribedMeters(double meters, UnitSystem unit) {
  final value = prescribedValue(meters, unit);
  return unit.isMetric ? value * metersPerKilometer : value * metersPerMile;
}

/// "7 km", "4 mi".
String formatPrescribed(double meters, UnitSystem unit) =>
    '${prescribedValue(meters, unit).toStringAsFixed(0)} '
    '${unit.distanceSuffix}';

/// A week's prescribed total, as the sum of what the runner was told.
///
/// Converting the exact stored total instead would print a header that does not
/// match the rows beneath it: five sessions rounded down to whole miles add to
/// 24, while 40 km converts to 25.
String formatPrescribedTotal(Iterable<double> meters, UnitSystem unit) {
  final total = meters.fold<double>(
    0,
    (sum, m) => sum + prescribedValue(m, unit),
  );
  return '${total.toStringAsFixed(0)} ${unit.distanceSuffix}';
}

/// How far a run may be from what was asked and still be that session.
///
/// Twelve per cent, with a floor so short sessions are not held to a tighter
/// standard than long ones. A 10 km session is satisfied by anything from about
/// 8.8 to 11.2 km — which covers a route that came up short, a watch that
/// under-read, and a runner who stopped at the end of their street.
const double sessionTolerance = 0.12;

/// The smallest band, for sessions short enough that a percentage would be
/// unreasonably tight.
const double sessionToleranceFloorMeters = 500;

/// The band of distances that count as [session].
({double low, double high}) toleranceFor(double prescribedMeters) {
  final band = math.max(
    prescribedMeters * sessionTolerance,
    sessionToleranceFloorMeters,
  );
  return (
    low: math.max(0, prescribedMeters - band),
    high: prescribedMeters + band,
  );
}

/// Whether [actualMeters] counts as having done [session], for a runner reading
/// in [unit].
///
/// Banded around **what they were told**, not around what is stored. A 4 km
/// session reads as "2 mi", and a runner who runs exactly two miles covers
/// 3.2 km — nearly 20% under the stored number, and outside any sane tolerance
/// on it. They did the session they were given, and this says so.
///
/// A session with no distance — strength, or a commitment the runner did not
/// put a number on — is satisfied by any run at all: they said they would turn
/// up, not how far.
bool fulfils(
  PlannedSession session,
  double actualMeters, {
  UnitSystem unit = UnitSystem.metric,
}) {
  if (!session.kind.isRun) return false;
  if (session.distanceMeters <= 0) return actualMeters > 0;
  final band = toleranceFor(prescribedMeters(session.distanceMeters, unit));
  return actualMeters >= band.low && actualMeters <= band.high;
}

/// The standard distances runners call by name rather than by number.
///
/// Stored exactly — a marathon is 42,195 m and every pace projection depends on
/// that — and *shown* as the word. "Marathon" is what the runner calls it;
/// "26 mi" is a rounding of 26.2, and "42 km" is a rounding of 42.195. The name
/// is both shorter and more accurate than either.
const List<({double meters, String name})> _namedDistances =
    <({double meters, String name})>[
      (meters: 5000, name: '5K'),
      (meters: 10000, name: '10K'),
      (meters: 21097.5, name: 'Half marathon'),
      (meters: 42195, name: 'Marathon'),
    ];

/// How close a goal has to be to a named distance to be that distance. Fifty
/// metres — enough for a profile that stored 21097 or 21098, nowhere near
/// enough to swallow a genuinely different goal.
const double _nameTolerance = 50;

/// The name of a standard distance, or null if it is not one.
String? raceName(double meters) {
  for (final race in _namedDistances) {
    if ((meters - race.meters).abs() <= _nameTolerance) return race.name;
  }
  return null;
}

/// A goal as the runner would say it: "Marathon" where there is a word for it,
/// and a rounded distance where there is not.
String describeGoal(double meters, UnitSystem unit) =>
    raceName(meters) ?? formatPrescribed(meters, unit);
