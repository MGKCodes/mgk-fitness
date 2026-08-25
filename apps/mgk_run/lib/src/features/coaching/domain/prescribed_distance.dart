import 'dart:math' as math;

import 'package:mgk_units/mgk_units.dart';
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
///
/// **Prescriptions round; achievements do not.** Everything here is for a
/// number the plan *asked* for. A distance the runner actually covered is not a
/// prescription and never comes through these functions: 10.18 km is earned
/// precision, and flattening it to "10 km" tells someone their run was smaller
/// than it was. The test is whose number it is — the plan's, or the runner's.

/// Prescribed distances are stored on a whole-kilometre grid, never below one.
///
/// This is the *stored* rounding, applied when a session is generated
/// (`plan_builder.dart`), and it exists so the plan's own arithmetic stays
/// clean: the arc and the week cannot disagree about the same session, and
/// nothing downstream has to re-derive a round number from 4,137 m. What the
/// runner **reads** is rounded again, in their own unit — see [prescribedValue].
///
/// It does not, on its own, keep the long run clear of a Tuesday. A whole
/// kilometre is a coarser step than the clearance the week shape can deliver
/// (`_underLongRun` in `plan_builder.dart` explains why it cannot be widened),
/// so on a low-volume week the long run and the hardest easy day land on the
/// same stored number. A tie is harmless — the long run is the session whose
/// kind says so, never the biggest number in the week. Being *passed* is not,
/// and the builder caps the rest of the week at the long run rather than
/// expecting this to sort it out.
double roundPrescribed(double meters) {
  if (meters <= 0) return 0;
  return math.max(1000, (meters / 1000).round() * 1000).toDouble();
}

/// The furthest [roundPrescribed] can move a number: half a kilometre.
///
/// Anything comparing a stored session against a figure the plan worked out
/// exactly — the skeleton's own long run, say — has to allow for this, or it is
/// reporting the grid as a discrepancy.
const double prescribedGridSlackMeters = 500;

/// Puts a set of sessions on the grid **without losing the week**.
///
/// Rounding each session on its own is the obvious thing and it quietly deletes
/// training: seven days of 1.14 km each fall to 1 km, and an 8 km week comes
/// back as 7 — an eighth of the runner's volume gone to a display decision. The
/// validator catches it as `week_volume`, which is the right complaint about
/// the wrong culprit.
///
/// So the kilometres are apportioned rather than rounded one by one. Every
/// session takes the whole kilometres it has earned, and the ones left over go
/// to the sessions that came closest to earning another — the largest-remainder
/// method, the same one used to turn vote shares into seats. The total survives,
/// which is the only reason the grid is safe to apply at all.
///
/// Order survives *within one call*: a session with a bigger raw number never
/// ends up with fewer kilometres than a smaller one, because with equal whole
/// parts the bigger number also has the bigger remainder and is served first.
/// It says nothing about a number rounded somewhere else — a caller mixing this
/// with [roundPrescribed] on the same week has two roundings that can go
/// opposite ways, and has to keep the order itself.
List<double> prescribeAcross(Iterable<double> meters) {
  final raw = meters.toList(growable: false);
  if (raw.isEmpty) return const <double>[];

  // Never fewer whole kilometres than there are sessions: nothing rounds away
  // to nothing, so a week of five sessions is at least five kilometres however
  // little was asked for.
  final total = raw.fold<double>(0, (sum, m) => sum + math.max(0, m));
  final target = math.max(raw.length, (total / 1000).round());

  final km = <int>[for (final m in raw) math.max(1, (m / 1000).floor())];
  final byRemainder = List<int>.generate(raw.length, (i) => i)
    ..sort((a, b) {
      final remainderA = raw[a] / 1000 - (raw[a] / 1000).floor();
      final remainderB = raw[b] / 1000 - (raw[b] / 1000).floor();
      final byFraction = remainderB.compareTo(remainderA);
      return byFraction != 0 ? byFraction : raw[b].compareTo(raw[a]);
    });

  var spare = target - km.fold<int>(0, (sum, k) => sum + k);
  for (var i = 0; spare > 0; i++) {
    km[byRemainder[i % byRemainder.length]]++;
    spare--;
  }
  // Or hand back, taking from the sessions that earned least first. Stops when
  // every session is at the floor, which is the one case where the week cannot
  // be held: a total so small that a kilometre each already overshoots it.
  while (spare < 0) {
    final before = spare;
    for (final i in byRemainder.reversed) {
      if (spare == 0) break;
      if (km[i] > 1) {
        km[i]--;
        spare++;
      }
    }
    if (spare == before) break;
  }

  return <double>[for (final k in km) k * 1000.0];
}

/// The prescription as the runner reads it: a whole number in **their** unit.
///
/// A miles runner is told "4 mi", not "4.3 mi". The point of rounding is ease of
/// use, and a number that is round in a unit the runner does not think in is not
/// round to them.
///
/// **The unit rounding happens at display, and only at display.** The stored
/// plan is metric — on the whole-kilometre grid [roundPrescribed] puts it on,
/// but metric — so that switching units in Settings re-reads the same plan
/// rather than rewriting it. A toggle must never mutate someone's training. It
/// also means two runners on the same plan are on the same plan; only the
/// sentence they are shown differs.
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

/// The metres of [_namedDistances], shortest first.
///
/// Public so the records table can be checked against it. `best_effort.dart`
/// keeps its own copy of these four numbers — it cannot import this file, since
/// every feature depends on `recording/domain` and it depends on none of them —
/// and a test asserts the two lists are identical. Adding a fifth named
/// distance to one and not the other then fails loudly, instead of quietly
/// producing a record with no name for it or a name with no record.
final List<double> namedRaceDistanceMeters = List<double>.unmodifiable(<double>[
  for (final race in _namedDistances) race.meters,
]);

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
