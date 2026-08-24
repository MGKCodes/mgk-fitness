import 'run_point.dart';
import 'run_split.dart';

/// A finished run, shaped for display. All magnitudes are metric; conversion to
/// the user's units happens at the display layer.
///
/// Optional fields are genuinely optional — a treadmill or manual run has no
/// route and no splits, and HR/elevation may be absent (a denied HealthKit read
/// is indistinguishable from no data). The UI designs for absence.
class RunSummary {
  const RunSummary({
    this.id,
    required this.startedAt,
    required this.duration,
    required this.distanceMeters,
    this.avgPaceSecondsPerKm,
    this.elevationGainMeters,
    this.avgHr,
    this.maxHr,
    this.caloriesEst,
    this.steps,
    this.type = 'outdoor',
    this.points = const <RunPoint>[],
    this.splits = const <RunSplit>[],
  });

  /// The stored run's id, when this summary came from a row.
  ///
  /// Nullable because a summary is also built from a recording in progress and
  /// from seeded demo data, neither of which is a row yet. A null id is what
  /// makes a run un-editable, which is correct: there is nothing to edit.
  final String? id;

  final DateTime startedAt;
  final Duration duration;
  final double distanceMeters;

  final double? avgPaceSecondsPerKm;
  final double? elevationGainMeters;
  final int? avgHr;
  final int? maxHr;

  /// A derived estimate — always labelled as such in the UI, never a measurement.
  final double? caloriesEst;

  /// Steps taken, when Health has them.
  ///
  /// **Nothing writes this yet**, and the summary is honest about that by
  /// simply not drawing the tile: absent is absent, never a zero and never an
  /// error (CLAUDE.md rule 6 — a denied Health read is indistinguishable from
  /// no data). It is here so the shape of the summary is settled before the
  /// read that fills it lands, which is Phase 2 of the 1.0.0 plan; storing it
  /// will want a `runs.steps` column, which this field deliberately does not
  /// invent.
  final int? steps;

  /// `outdoor` | `treadmill` | `manual`.
  final String type;

  final List<RunPoint> points;
  final List<RunSplit> splits;

  bool get hasRoute => points.length >= 2;
}
