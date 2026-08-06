import 'runner_profile.dart';

/// What kind of plan a runner is on — see
/// [ADR-0011](../../../../../docs/decisions/0011-a-plan-has-a-shape.md).
///
/// Four, because these are the combinations that change what the app must *do*:
/// what a week contains, which invariants apply, and what the coach is told.
/// They are not personas. A first 5 km with a date entered is a [block]; the
/// same runner without one is a [horizon].
///
/// **Never branch on this in the presentation layer.** A shape decides what is
/// *in* a week, never what a week looks like. Everything a screen needs is
/// already computed for it — see [PlanHeadline]. The failure this forbids is
/// four half-maintained Plan tabs.
enum PlanShape {
  /// A dated race build: ramp, peak, taper. Position is "week n of N".
  block,

  /// A repeating pattern held indefinitely — parkrun every Saturday, three runs
  /// a week. No ramp and no taper; the invariant is consistency.
  rhythm,

  /// A distance to reach with no race entered. Ramps like a [block] but has
  /// nothing to taper into; position is progress toward being ready.
  horizon,

  /// No stated intent. The runs are still recorded and the coach still answers;
  /// there is simply nothing to plan against.
  log;

  /// Whether the training arc climbs toward something.
  bool get progresses => this == block || this == horizon;

  /// Whether there is an endpoint to taper into. Only a [block] has one — a
  /// taper without a date is a guess about a race that has not been entered.
  bool get tapers => this == block;

  /// Whether the plan produces weeks at all.
  bool get hasWeeks => this != log;
}

/// The shape of the plan this profile describes.
///
/// **Derived, never stored.** A stored shape is one more field that can
/// disagree with the data it describes — a plan marked `block` with no event
/// date would be a contradiction the type system happily allows. Deriving it
/// means the shape is always exactly what the runner told us.
PlanShape shapeOf(RunnerProfile profile) {
  final hasGoal = profile.goalDistanceMeters != null;
  final hasDate = profile.eventDate != null;
  if (hasGoal && hasDate) return PlanShape.block;
  if (hasGoal) return PlanShape.horizon;
  if (profile.commitments.isNotEmpty || profile.daysPerWeek > 0) {
    return PlanShape.rhythm;
  }
  return PlanShape.log;
}

/// A session the runner has committed to repeating — "parkrun, Saturdays, 5 km".
///
/// The building block of a [PlanShape.rhythm]. It carries a [label] because
/// "parkrun" is what the runner calls it, and a plan that renamed it "Saturday
/// 5 km time trial" would be technically right and would not be their week.
class PlanCommitment {
  const PlanCommitment({
    required this.weekday,
    this.distanceMeters,
    this.label,
    this.timed = false,
  });

  /// `DateTime.monday`..`DateTime.sunday`.
  final int weekday;

  /// How far, when the runner said. Null means "a run, length up to them".
  final double? distanceMeters;

  /// What they call it. Null for an unnamed regular run.
  final String? label;

  /// Whether they time it. A timed commitment is a repeating measurement, which
  /// is what lets the coach answer "am I getting quicker" for a runner who will
  /// never enter a race.
  final bool timed;
}

/// Commitments as one string: `weekday|meters|timed|label`, rows joined by `;`.
///
/// Flat because SQLite has no array type and the local mirror stays flat on
/// purpose (docs/architecture/data-model.md). A label containing `|` or `;`
/// would corrupt the row, so both are stripped rather than escaped — a runner
/// naming their parkrun with a pipe is not worth an escaping scheme.
String encodeCommitments(List<PlanCommitment> commitments) => commitments
    .map(
      (c) => <String>[
        '${c.weekday}',
        c.distanceMeters?.toStringAsFixed(0) ?? '',
        c.timed ? '1' : '0',
        (c.label ?? '').replaceAll(RegExp(r'[|;]'), ' ').trim(),
      ].join('|'),
    )
    .join(';');

/// Reads [encodeCommitments] back. Tolerant: a row it cannot parse is dropped
/// rather than throwing, because a corrupt commitment must not cost the runner
/// their whole plan.
List<PlanCommitment> decodeCommitments(String? raw) {
  if (raw == null || raw.isEmpty) return const <PlanCommitment>[];
  final out = <PlanCommitment>[];
  for (final row in raw.split(';')) {
    if (row.isEmpty) continue;
    final parts = row.split('|');
    if (parts.length < 3) continue;
    final weekday = int.tryParse(parts[0]);
    if (weekday == null || weekday < 1 || weekday > 7) continue;
    final label = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
    out.add(
      PlanCommitment(
        weekday: weekday,
        distanceMeters: double.tryParse(parts[1]),
        timed: parts[2] == '1',
        label: label,
      ),
    );
  }
  return out;
}
