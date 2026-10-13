import 'best_effort.dart';
import 'run_point.dart';
import 'run_race.dart';
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
    this.notes,
    this.type = 'outdoor',
    this.points = const <RunPoint>[],
    this.splits = const <RunSplit>[],
    this.bestEfforts = const <BestEffort>[],
    this.race,
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

  /// What is written on the run: the runner's own note, or the app's where it
  /// finished the run itself (`kRecoveredRunNote`). Null or blank for most.
  final String? notes;

  /// `outdoor` | `treadmill` | `manual`.
  final String type;

  final List<RunPoint> points;
  final List<RunSplit> splits;

  /// The standard distances this run holds a time for, shortest first —
  /// the fastest continuous 5 km, 10 km, half or full **inside** it, not its
  /// own time over its own distance (ADR-0026).
  ///
  /// Empty for nearly every run, and empty means the same two things it means
  /// in storage: the run was shorter than 5 km, or it has no trace to search
  /// because it was typed in by hand or arrived from Health. It is never a
  /// stand-in for the whole-run time, which is a different measurement.
  ///
  /// Unlike [points] and [splits] this is carried by the log's read as well as
  /// by a single run's, because the records a runner sees on Profile are a fold
  /// over every run. Four numbers per run is affordable where a trace is not.
  final List<BestEffort> bestEfforts;

  /// The race this run was, or null for a training run — which is nearly all
  /// of them.
  ///
  /// Carried by the log's read as well as a single run's, like [bestEfforts]
  /// and for the same reason: a race screen compares this one against the
  /// runner's earlier races at the distance, and that is a fold over the log.
  final RunRace? race;

  bool get hasRoute => points.length >= 2;

  /// The efforts this run contributes to the runner's records: its
  /// [bestEfforts], except at the distance it was raced over, where the race
  /// counts as its own time.
  ///
  /// **A race's GPS stretch is not its time.** The phone reads long on a race
  /// course, so the fastest 21.0975 km inside a half recorded as 21.69 km is
  /// shorter than the course and quicker than the result: Sunday's was 1:57:40
  /// against a chip time of 2:00:30. Counting it would make the runner's half
  /// marathon figure a number they never ran. The official time is used where
  /// they gave one, the phone's whole-run time where they did not
  /// ([RunRace.timeFor]) — both are times for the course (ADR-0049).
  ///
  /// A race at a distance with no record (a 10-miler) changes nothing, and a
  /// race with no trace — typed in, or recorded on a watch — still counts at
  /// its distance, which is the one way a runner with no route gets a figure.
  List<BestEffort> get recordEfforts {
    final raced = race;
    if (raced == null) return bestEfforts;
    double? at;
    for (final meters in kRecordDistancesMeters) {
      // Fifty metres, the tolerance `raceName` names a distance by, so a half
      // entered as 21,097.5 and one typed as 21.1 km are the same record.
      if ((raced.distanceMeters - meters).abs() <= 50) at = meters;
    }
    if (at == null) return bestEfforts;
    return <BestEffort>[
      for (final effort in bestEfforts)
        if (effort.distanceMeters != at) effort,
      BestEffort(distanceMeters: at, duration: raced.timeFor(duration)),
    ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  }

  /// This summary with its race replaced, for the screen that has just marked
  /// or corrected it. Everything else is carried across untouched.
  RunSummary withRace(RunRace? race) => RunSummary(
    id: id,
    startedAt: startedAt,
    duration: duration,
    distanceMeters: distanceMeters,
    avgPaceSecondsPerKm: avgPaceSecondsPerKm,
    elevationGainMeters: elevationGainMeters,
    elevationMaxMeters: elevationMaxMeters,
    avgHr: avgHr,
    maxHr: maxHr,
    caloriesEst: caloriesEst,
    steps: steps,
    notes: notes,
    type: type,
    points: points,
    splits: splits,
    bestEfforts: bestEfforts,
    race: race,
  );
}
