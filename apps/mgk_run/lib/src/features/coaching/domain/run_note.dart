import 'dart:math' as math;

import '../../../core/units/distance.dart';
import '../../../core/units/pace.dart';
import '../../../core/units/unit_system.dart';
import '../../recording/domain/run_split.dart';
import '../../recording/domain/run_summary.dart';
import 'training_plan.dart';

/// What the coach has to say about **one run**, shown on that run's summary.
///
/// `CoachNote` speaks about a runner's training as a whole ("you're turning
/// up"). This speaks about a single run, which means it has more to work with:
/// it can compare the run to the runs around it, to the session that was
/// prescribed, and to its own splits.
///
/// **Derived in Dart, not generated.** The same rule that governs plans: a
/// remark about someone's training has to be true, and computing it from their
/// runs is the cheapest way to guarantee that. Every claim here is checkable
/// against the data behind it, and the thresholds exist so that nothing is
/// claimed on the strength of measurement noise — a run 1% further than your
/// previous longest is not a record, it is GPS.
///
/// **One note per run.** The candidates are ranked (see [forRun]) and the first
/// that holds is the one shown. A coach who says five things about one run is
/// not coaching. Where nothing holds, the answer is null — silence is a normal
/// and common output, not an error, and absent data (no HR, no elevation, no
/// splits, no plan) simply removes candidates rather than producing a state.
class RunNote {
  const RunNote({
    required this.headline,
    required this.detail,
    required this.kind,
  });

  /// One line, in the coach's voice.
  final String headline;

  /// The evidence behind it, so the remark is checkable rather than flattering.
  final String detail;

  final RunNoteKind kind;

  /// The single most notable true thing about [run], or null if there is
  /// nothing honest to say about it.
  ///
  /// [history] is the runner's other runs; passing the whole history is fine,
  /// since [run] is filtered out of it. Two different windows are used on
  /// purpose:
  ///
  ///  * **Records** are checked against *every* other run, before or after.
  ///    A record is a claim about now, so a run that has since been beaten no
  ///    longer holds one — opening an old run must not congratulate you on a
  ///    best you no longer have.
  ///  * **"Than usual"** comparisons use only the runs in the six weeks
  ///    *before* this one, because "usual" means what you were doing at the
  ///    time.
  ///
  /// [planned] is the session prescribed for the day this run happened, when
  /// the run fell on a planned day; null otherwise.
  ///
  /// [unit] is only ever handed to [Distance.format] and [Pace.format]. Nothing
  /// here branches on it and every magnitude stays metric until that call —
  /// the note is a display string, so its numbers convert at display like any
  /// other.
  ///
  /// The ranking, loudest first:
  ///
  ///  1. the furthest they have ever run;
  ///  2. their quickest at a comparable distance;
  ///  3. a run well over or well short of the session prescribed;
  ///  4. their pace at a lower heart rate than usual;
  ///  5. how the run was paced, from its splits;
  ///  6. a session hit as prescribed;
  ///  7. a notably hilly run;
  ///  8. how it sat against their recent runs.
  ///
  /// A record outranks everything because it is what a runner would tell
  /// someone else. Missing the session outranks how the run was paced, because
  /// a runner needs to know they are off plan before they hear about their
  /// second half; hitting the session sits *below* pacing, because doing what
  /// was asked is expected — how it was run is the new information.
  static RunNote? forRun(
    RunSummary run, {
    List<RunSummary> history = const <RunSummary>[],
    PlannedSession? planned,
    UnitSystem unit = UnitSystem.metric,
  }) {
    if (run.distanceMeters <= 0) return null;

    final others = _others(run, history);
    final recent = _recent(run, others);

    return _furthestEver(run, others, unit) ??
        _quickestAtThisDistance(run, others, unit) ??
        _offTheSession(run, planned, unit) ??
        _lowerEffort(run, recent) ??
        _howItWasPaced(run, unit) ??
        _onTheSession(run, planned, unit) ??
        _hilly(run, recent) ??
        _furtherThanUsual(run, recent, unit) ??
        _pacedAgainstUsual(run, recent, unit);
  }
}

/// What the coach noticed. Available for future styling; the design language
/// keeps them all monochrome for now (ADR-0009).
enum RunNoteKind { record, plan, effort, pacing, terrain, context }

// ---------------------------------------------------------------------------
// Thresholds. Each one exists to stop a claim being made on noise.
// ---------------------------------------------------------------------------

/// Below this, pace is a sprint for a bus rather than a run, and distance is
/// not a record at anything.
const double _minMeaningfulMeters = 1000;

/// A distance record has to clear the old one by a real margin — 5%, and never
/// less than 200 m. GPS distance is noisy at the edges, so 5.2 km after a 5.0 km
/// is not a personal best; it is the same run measured twice.
const double distanceRecordFactor = 1.05;
const double distanceRecordMeters = 200;

/// Whether [candidate] beats [best] by enough to be called a record.
///
/// Shared with [CoachNote] so the home page and the run summary cannot disagree
/// about what a personal best is — one congratulating a runner on a metre the
/// other refuses to count is worse than neither doing it.
bool beatsDistanceRecord(double candidate, double best) =>
    candidate >= best * distanceRecordFactor &&
    candidate - best >= distanceRecordMeters;

/// A pace record has to clear the old one by 1% (about 3 s/km at 5:00/km).
/// A second per kilometre is not an improvement, it is rounding.
const double _paceRecordFactor = 0.99;

/// Runs count as "a similar distance" within this band of each other. A 5 km
/// compares against 4–6 km, not against a 400 m effort or a half marathon.
const double _recordDistanceBand = 0.2;
const double _usualDistanceBand = 0.25;

/// A record claim needs something to have beaten: at least two comparable runs,
/// so "faster than every run you've logged at this distance" means something.
const int _minComparableRuns = 2;

/// "Usual" needs a few runs behind it, taken from the six weeks before the run.
const int _recentWindowDays = 42;
const int _recentRunLimit = 10;
const int _minRecentRuns = 3;

/// A run needs four full splits before its two halves are a pacing story. With
/// two, there is no story to tell.
const int _minSplitsForPacing = 4;

/// Half-to-half pace difference that counts as a split rather than an even run.
const double _splitDifference = 0.03;

/// Prescribed-distance bands: within 10% is the session; beyond 25% either way
/// is a deviation worth naming. In between, nothing is said about the plan.
const double _onPlanBand = 0.10;
const double _offPlanBand = 0.25;

/// Climb per kilometre at which a route stops being flat.
const double _hillyMetersPerKm = 15;
const double _hillyFactor = 1.8;

/// Beats per minute below the recent median that counts as a lower heart rate.
const double _hrDrop = 4;

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

/// The runs that can inform a note about [run] — everything except the run
/// itself. Callers usually pass their whole history, so the run is removed by
/// identity and by start time (a run cannot start twice).
List<RunSummary> _others(RunSummary run, List<RunSummary> history) => history
    .where(
      (r) =>
          !identical(r, run) &&
          r.startedAt != run.startedAt &&
          r.distanceMeters > 0,
    )
    .toList();

/// The runs leading up to [run] — what "usual" meant at the time.
List<RunSummary> _recent(RunSummary run, List<RunSummary> others) {
  final before =
      others
          .where(
            (r) =>
                r.startedAt.isBefore(run.startedAt) &&
                run.startedAt.difference(r.startedAt).inDays <=
                    _recentWindowDays,
          )
          .toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return before.take(_recentRunLimit).toList();
}

// ---------------------------------------------------------------------------
// The candidates, in rank order
// ---------------------------------------------------------------------------

/// 1. The furthest they have ever run.
RunNote? _furthestEver(
  RunSummary run,
  List<RunSummary> others,
  UnitSystem unit,
) {
  if (!_isMeasured(run) || run.distanceMeters < _minMeaningfulMeters) {
    return null;
  }
  if (others.isEmpty) return null;

  final priorLongest = others
      .map((r) => r.distanceMeters)
      .reduce((a, b) => a > b ? a : b);
  if (!beatsDistanceRecord(run.distanceMeters, priorLongest)) return null;

  return RunNote(
    headline: 'Furthest you’ve been.',
    detail:
        '${_distance(run.distanceMeters, unit)} — further than any other run '
        'in your history.',
    kind: RunNoteKind.record,
  );
}

/// 2. Their quickest over a comparable distance.
RunNote? _quickestAtThisDistance(
  RunSummary run,
  List<RunSummary> others,
  UnitSystem unit,
) {
  if (!_isMeasured(run) || run.distanceMeters < _minMeaningfulMeters) {
    return null;
  }
  final pace = _paceSeconds(run);
  if (pace == null) return null;

  final rivals = others
      .where(
        (r) =>
            r.distanceMeters >= _minMeaningfulMeters &&
            _isComparable(
              r.distanceMeters,
              run.distanceMeters,
              _recordDistanceBand,
            ),
      )
      .map(_paceSeconds)
      .whereType<double>()
      .toList();
  if (rivals.length < _minComparableRuns) return null;

  final best = rivals.reduce(math.min);
  if (pace > best * _paceRecordFactor) return null;

  return RunNote(
    headline: 'Quickest you’ve run this distance.',
    detail:
        '${_pace(pace, unit)} over ${_distance(run.distanceMeters, unit)} — '
        'faster than every run you’ve logged at a similar distance.',
    kind: RunNoteKind.record,
  );
}

/// 3. Well over, or well short of, the session that was prescribed.
RunNote? _offTheSession(
  RunSummary run,
  PlannedSession? planned,
  UnitSystem unit,
) {
  final target = _prescribed(planned);
  if (target == null) return null;
  final ratio = run.distanceMeters / target;

  if (ratio >= 1 + _offPlanBand) {
    final easyDay =
        planned!.kind == SessionKind.easy ||
        planned.kind == SessionKind.recovery;
    return RunNote(
      headline: 'More than the session asked for.',
      detail:
          'The plan had ${_distance(target, unit)}; you ran '
          '${_distance(run.distanceMeters, unit)}.'
          '${easyDay ? ' Easy days only do their job if they stay easy.' : ''}',
      kind: RunNoteKind.plan,
    );
  }
  if (ratio <= 1 - _offPlanBand) {
    return RunNote(
      headline: 'Short of the session.',
      detail:
          'The plan had ${_distance(target, unit)}; you ran '
          '${_distance(run.distanceMeters, unit)}. One session off plan '
          'changes very little.',
      kind: RunNoteKind.plan,
    );
  }
  return null;
}

/// 4. The same pace as usual, at a lower heart rate.
///
/// Stated as the observation it is, not as a fitness verdict: heart rate moves
/// with heat, sleep and a badly seated strap as well as with training.
RunNote? _lowerEffort(RunSummary run, List<RunSummary> recent) {
  final hr = run.avgHr;
  final pace = _paceSeconds(run);
  if (hr == null || pace == null) return null;

  final peers = recent
      .where(
        (r) =>
            r.avgHr != null &&
            _paceSeconds(r) != null &&
            _isComparable(
              r.distanceMeters,
              run.distanceMeters,
              _usualDistanceBand,
            ),
      )
      .toList();
  if (peers.length < _minComparableRuns) return null;

  final medianPace = _median(peers.map((r) => _paceSeconds(r)!).toList());
  final medianHr = _median(peers.map((r) => r.avgHr!.toDouble()).toList());

  // No slower than usual, and a heart rate genuinely below it. A slower run at
  // a lower heart rate is just a slower run.
  if (pace > medianPace * 1.01) return null;
  if (hr > medianHr - _hrDrop) return null;

  return const RunNote(
    headline: 'Same pace, lower heart rate.',
    detail:
        'You held your recent pace with your average heart rate below where '
        'it has been sitting. One run isn’t a trend, but that is the '
        'direction it should move.',
    kind: RunNoteKind.effort,
  );
}

/// 5. How the run was paced, from its splits.
RunNote? _howItWasPaced(RunSummary run, UnitSystem unit) {
  final splits = _measuredSplits(run.splits);
  if (splits.length < _minSplitsForPacing) return null;

  // An odd number of splits drops the middle one rather than letting it count
  // for both halves.
  final half = splits.length ~/ 2;
  final first = _paceOfSplits(splits.take(half));
  final second = _paceOfSplits(splits.skip(splits.length - half));
  if (first == null || second == null) return null;

  final change = (first - second) / first;
  if (change >= _splitDifference) {
    return RunNote(
      headline: 'You finished faster than you started.',
      detail:
          'First half ${_pace(first, unit)}, second half ${_pace(second, unit)}'
          '. That is the way round to do it.',
      kind: RunNoteKind.pacing,
    );
  }
  if (change <= -_splitDifference) {
    return RunNote(
      headline: 'You faded over the second half.',
      detail:
          'First half ${_pace(first, unit)}, second half ${_pace(second, unit)}'
          '. Setting off a shade slower usually finishes quicker.',
      kind: RunNoteKind.pacing,
    );
  }
  return null;
}

/// 6. The session, run as prescribed.
RunNote? _onTheSession(
  RunSummary run,
  PlannedSession? planned,
  UnitSystem unit,
) {
  final target = _prescribed(planned);
  if (target == null) return null;
  final ratio = run.distanceMeters / target;
  if (ratio < 1 - _onPlanBand || ratio > 1 + _onPlanBand) return null;

  return RunNote(
    headline: 'That’s the session.',
    detail:
        'The plan had ${_distance(target, unit)}; you ran '
        '${_distance(run.distanceMeters, unit)}.',
    kind: RunNoteKind.plan,
  );
}

/// 7. A notably hilly run, relative to where this runner usually runs.
///
/// No figure is quoted: elevation has no display-unit conversion in the app, so
/// the note stays comparative rather than printing metres at a runner who reads
/// in feet.
RunNote? _hilly(RunSummary run, List<RunSummary> recent) {
  final gain = run.elevationGainMeters;
  if (gain == null || run.distanceMeters < _minMeaningfulMeters) return null;

  final climb = _climbPerKm(run);
  if (climb == null || climb < _hillyMetersPerKm) return null;

  final peers = recent
      .where(
        (r) =>
            r.elevationGainMeters != null &&
            r.distanceMeters >= _minMeaningfulMeters,
      )
      .map(_climbPerKm)
      .whereType<double>()
      .toList();
  if (peers.length < _minComparableRuns) return null;
  if (climb < _median(peers) * _hillyFactor) return null;

  return const RunNote(
    headline: 'That was a hilly one.',
    detail:
        'Far more climbing, for the distance, than your recent runs. Pace '
        'tells you less on a day like that.',
    kind: RunNoteKind.terrain,
  );
}

/// 8a. Further than they have been going.
RunNote? _furtherThanUsual(
  RunSummary run,
  List<RunSummary> recent,
  UnitSystem unit,
) {
  if (recent.length < _minRecentRuns) return null;
  final usual = _median(recent.map((r) => r.distanceMeters).toList());
  if (usual <= 0 || run.distanceMeters < usual * 1.25) return null;

  return RunNote(
    headline: 'Further than you’ve been going.',
    detail:
        '${_distance(run.distanceMeters, unit)}, against recent runs nearer '
        '${_distance(usual, unit)}.',
    kind: RunNoteKind.context,
  );
}

/// 8b. Quicker, or easier, than their recent runs of this length.
RunNote? _pacedAgainstUsual(
  RunSummary run,
  List<RunSummary> recent,
  UnitSystem unit,
) {
  if (recent.length < _minRecentRuns) return null;
  final pace = _paceSeconds(run);
  if (pace == null) return null;

  final peers = recent
      .where(
        (r) => _isComparable(
          r.distanceMeters,
          run.distanceMeters,
          _usualDistanceBand,
        ),
      )
      .map(_paceSeconds)
      .whereType<double>()
      .toList();
  if (peers.length < _minComparableRuns) return null;

  final usual = _median(peers);
  if (pace <= usual * 0.97) {
    return RunNote(
      headline: 'Quicker than your usual.',
      detail:
          '${_pace(pace, unit)}, against about ${_pace(usual, unit)} on your '
          'recent runs of this length.',
      kind: RunNoteKind.context,
    );
  }

  // Calling a run easy is a claim about intent, so it takes more evidence than
  // calling one quick — and it is never made about a run up a hill, where the
  // slower pace is the terrain talking.
  final climb = _climbPerKm(run);
  if (climb != null && climb >= _hillyMetersPerKm) return null;
  if (pace >= usual * 1.05) {
    return RunNote(
      headline: 'An easier one.',
      detail:
          '${_pace(pace, unit)}, against about ${_pace(usual, unit)} on your '
          'recent runs of this length. Easy running is most of what builds a '
          'runner.',
      kind: RunNoteKind.context,
    );
  }
  return null;
}

// ---------------------------------------------------------------------------
// Derivation helpers
// ---------------------------------------------------------------------------

/// A manual entry is a runner's own estimate, typed in and rounded. It counts
/// towards the bar a record has to clear, but it can never take one.
bool _isMeasured(RunSummary run) => run.type != 'manual';

double? _paceSeconds(RunSummary run) {
  final stated = run.avgPaceSecondsPerKm;
  if (stated != null && stated > 0) return stated;
  if (run.distanceMeters <= 0 || run.duration.inSeconds <= 0) return null;
  return run.duration.inSeconds / (run.distanceMeters / 1000);
}

double? _climbPerKm(RunSummary run) {
  final gain = run.elevationGainMeters;
  if (gain == null || run.distanceMeters <= 0) return null;
  return gain / (run.distanceMeters / 1000);
}

bool _isComparable(double meters, double against, double band) =>
    meters >= against * (1 - band) && meters <= against * (1 + band);

/// The prescribed distance for a planned run, or null when the day was rest,
/// unplanned, or carried no distance.
double? _prescribed(PlannedSession? planned) {
  if (planned == null || !planned.kind.isRun) return null;
  return planned.distanceMeters > 0 ? planned.distanceMeters : null;
}

/// The full-length splits, in order. A trailing part-kilometre paces oddly over
/// a short distance, so it is left out of the pacing story rather than allowed
/// to invent a fade.
List<RunSplit> _measuredSplits(List<RunSplit> splits) {
  if (splits.isEmpty) return const <RunSplit>[];
  final longest = splits
      .map((s) => s.distanceMeters)
      .reduce((a, b) => a > b ? a : b);
  return splits
      .where(
        (s) => s.distanceMeters >= longest * 0.9 && s.duration.inSeconds > 0,
      )
      .toList()
    ..sort((a, b) => a.index.compareTo(b.index));
}

/// Distance-weighted pace across a set of splits.
double? _paceOfSplits(Iterable<RunSplit> splits) {
  var meters = 0.0;
  var seconds = 0;
  for (final split in splits) {
    meters += split.distanceMeters;
    seconds += split.duration.inSeconds;
  }
  if (meters <= 0 || seconds <= 0) return null;
  return seconds / (meters / 1000);
}

double _median(List<double> values) {
  final sorted = <double>[...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

String _distance(double meters, UnitSystem unit) =>
    Distance.meters(meters).format(unit);

String _pace(double secondsPerKm, UnitSystem unit) =>
    Pace.secondsPerKilometer(secondsPerKm).format(unit);
