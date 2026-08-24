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
    this.elevationMaxMeters,
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

  /// Total ascent — the sum of every rise on the route.
  final double? elevationGainMeters;

  /// The route's high point, in metres above sea level.
  ///
  /// Separate from [elevationGainMeters] because they answer different
  /// questions and routinely disagree: hill repeats are enormous gain over an
  /// unremarkable maximum, one long climb is the reverse.
  ///
  /// The two absences differ too. Null gain beside a real maximum is a flat
  /// run; both null is a trace with no barometric altitude, which is every
  /// trace this app currently records (ADR-0024).
  final double? elevationMaxMeters;

  final int? avgHr;
  final int? maxHr;

  /// A derived estimate — always labelled as such in the UI, never a measurement.
  final double? caloriesEst;

  /// Steps taken, when Health has them.
  ///
  /// Read from HealthKit over the run's window when the run finishes, and
  /// stored in `runs.steps`. Null far more often than not, and every one of the
  /// reasons is ordinary: the runner declined the Health read, the phone was
  /// not on them, the store answered too slowly, the run predates the column.
  /// A denied read is indistinguishable from no data (CLAUDE.md rule 6), so all
  /// of it renders as an absent tile — never a zero, never an error.
  final int? steps;

  /// `outdoor` | `treadmill` | `manual`.
  final String type;

  final List<RunPoint> points;
  final List<RunSplit> splits;

  bool get hasRoute => points.length >= 2;
}
