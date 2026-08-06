import '../../../core/units/distance.dart';
import '../../../core/units/pace.dart';
import '../../../core/units/unit_system.dart';
import '../../recording/domain/run_summary.dart';
import 'coach_statement.dart';
import 'stored_plan.dart';

/// The runner as a whole, measured against the only fair benchmark: themselves
/// a month ago.
///
/// **No plan talk here.** Where they are in a block — week 5 of 16, base or
/// taper, days to race day — is the Plan tab's subject, and Home's subject is
/// today. Profile is the long view: are they running more than they were, are
/// they turning up, are they getting quicker. A page that repeated the plan's
/// position would be the third screen saying the same thing.
///
/// **Derived in Dart, never generated.** The same rule that governs plans and
/// notes (CLAUDE.md rule 2): a claim about whether someone is progressing has
/// to be checkable against their runs. A model asked to summarise a runner will
/// call a month of nothing "building nicely", and the runner cannot tell that it
/// guessed. Dart counts; the conversation behind the card phrases.
///
/// This is also where *you versus you* stops being a slogan. Every comparison
/// on this card is against this runner's own history, because that is the only
/// history the app has and the only one that tells them anything they can act
/// on. The chat instructions in `supabase/functions/coach/surfaces.ts` hold the
/// coach to the same line when they inevitably ask how they compare to someone
/// else.
class TrainingStanding {
  const TrainingStanding({
    required this.headline,
    required this.detail,
    required this.verdict,
    this.facts = const StatementFacts(),
    this.factSheet = '',
  });

  /// The read, as a title — "Running more than you were", "Holding steady".
  ///
  /// A plain statement of the fact rather than a label for it. "Building" is
  /// what a coach calls this, and a runner should not have to know the word to
  /// read their own page.
  final String headline;

  /// The evidence for it, in their own numbers.
  final String detail;

  final StandingVerdict verdict;

  /// What a generated version of this line is allowed to say.
  ///
  /// Carried alongside the prose rather than parsed back out of it: the numbers
  /// are known here, at the point they are computed, and recovering them from a
  /// finished sentence would be guessing at our own output.
  final StatementFacts facts;

  /// The same reading as plain statements, for the model to phrase.
  ///
  /// Deliberately flat and a little graceless — it is not shown to anyone. The
  /// model's job is to turn this into a sentence, and [CoachStatement] checks
  /// that it did not add anything on the way.
  final String factSheet;

  /// The window each half of the comparison covers.
  static const int _windowDays = 28;

  /// How much a total has to move before it is a change rather than noise.
  static const double _materialShift = 0.12;

  /// And how much in absolute terms, so a runner doing 6 km a month is not told
  /// they are "building" over a single extra parkrun.
  static const double _materialMeters = 5000;

  /// Reads the runner's standing from their log.
  ///
  /// [runs] may be in any order. [now] is injected so the windows are testable.
  factory TrainingStanding.read({
    required List<RunSummary> runs,
    UnitSystem unit = UnitSystem.metric,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final sorted = <RunSummary>[...runs]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    if (sorted.isEmpty) {
      return const TrainingStanding(
        headline: 'Nothing recorded yet',
        detail:
            'Record a run and this becomes a picture of your training over '
            'time. Until then there is nothing to compare you against.',
        verdict: StandingVerdict.nothingYet,
        factSheet:
            'They have recorded no runs at all. Invite them to record '
            'one, or to talk about what they want to train for.',
      );
    }

    final daysSince = daysBetweenDates(sorted.first.startedAt, today);
    if (daysSince >= 14) {
      return TrainingStanding(
        headline: 'Been a while',
        detail:
            'Nothing recorded for $daysSince days. Start with an easy one. '
            'Coming back is a different job from carrying on, and the coach can '
            'tell you how to do it.',
        verdict: StandingVerdict.returning,
        facts: StatementFacts(allowedNumbers: <num>{daysSince}),
        factSheet:
            'They have not recorded a run for $daysSince days. Coming back is '
            'a different job from carrying on. Do not imply they have been '
            'training.',
      );
    }

    final recent = _within(sorted, today, from: _windowDays, to: 0);
    final prior = _within(
      sorted,
      today,
      from: _windowDays * 2,
      to: _windowDays,
    );
    final weeksRun = _weeksWithARun(sorted, today, window: 4);

    // Too little history to have a trend. Saying "building" off one window is a
    // claim about a direction, and a direction needs two points.
    if (prior.isEmpty) return _gettingStarted(sorted, unit);

    final recentMeters = _totalMeters(recent);
    final priorMeters = _totalMeters(prior);
    final paceLine = _paceLine(recent, prior, unit);
    final consistency = _consistencyLine(weeksRun);

    final volume =
        '${Distance.meters(recentMeters).format(unit, fractionDigits: 1)} '
        'in the last four weeks';
    final against = Distance.meters(
      priorMeters,
    ).format(unit, fractionDigits: 1);

    final change = priorMeters == 0
        ? 1.0
        : (recentMeters - priorMeters) / priorMeters;
    final material =
        (recentMeters - priorMeters).abs() >= _materialMeters &&
        change.abs() >= _materialShift;

    final trendFacts = _factsFor(
      recentMeters: recentMeters,
      priorMeters: priorMeters,
      weeksRun: weeksRun,
      recentPace: _averagePace(recent),
      priorPace: _averagePace(prior),
      unit: unit,
    );
    final sheet = _sheetFor(
      volume: volume,
      against: against,
      direction: !material
          ? 'about the same'
          : change > 0
          ? 'up'
          : 'down',
      weeksRun: weeksRun,
      recentPace: _averagePace(recent),
      priorPace: _averagePace(prior),
      unit: unit,
    );

    if (material && change > 0) {
      return TrainingStanding(
        headline: 'Running more than you were',
        detail:
            '$volume, up from $against the four before. '
            '$consistency$paceLine',
        verdict: StandingVerdict.building,
        facts: trendFacts,
        factSheet: sheet,
      );
    }

    if (material && change < 0) {
      return TrainingStanding(
        headline: 'Running less than you were',
        detail:
            '$volume, down from $against. That is only a problem if it was not '
            'deliberate. $consistency$paceLine',
        verdict: StandingVerdict.easing,
        facts: trendFacts,
        factSheet: sheet,
      );
    }

    return TrainingStanding(
      headline: weeksRun >= 4 ? 'Holding steady' : 'Running on and off',
      detail:
          '$volume, about the same as the four before. '
          '$consistency$paceLine',
      verdict: weeksRun >= 4 ? StandingVerdict.holding : StandingVerdict.patchy,
      facts: trendFacts,
      factSheet: sheet,
    );
  }

  /// A runner without a full window behind them. Their standing is that they
  /// are new, which is worth saying plainly rather than dressing as a trend.
  static TrainingStanding _gettingStarted(
    List<RunSummary> sorted,
    UnitSystem unit,
  ) {
    final total = Distance.meters(
      _totalMeters(sorted),
    ).format(unit, fractionDigits: 1);
    final count = sorted.length;
    return TrainingStanding(
      headline: 'Getting started',
      detail:
          '${count == 1 ? 'One run' : '$count runs'} and $total on the board. '
          'A few more weeks and there will be enough here to tell you which way '
          'you are heading.',
      verdict: StandingVerdict.gettingStarted,
      facts: StatementFacts(
        allowedNumbers: <num>{
          count,
          Distance.meters(_totalMeters(sorted)).inDisplayUnit(unit),
        },
      ),
      factSheet:
          'They have recorded $count ${count == 1 ? 'run' : 'runs'}, $total in '
          'total, and have no earlier month to compare against. Do not claim a '
          'direction: there is not enough history for one.',
    );
  }

  /// The numbers a generated line may use, in the unit it will be written in.
  ///
  /// Display units, not metres: the model writes "64.0 km", so 64.0 is what the
  /// validator has to recognise. Storage stays metric either way (rule 4).
  static StatementFacts _factsFor({
    required double recentMeters,
    required double priorMeters,
    required int weeksRun,
    required double? recentPace,
    required double? priorPace,
    required UnitSystem unit,
  }) {
    final recent = Distance.meters(recentMeters).inDisplayUnit(unit);
    final prior = Distance.meters(priorMeters).inDisplayUnit(unit);
    return StatementFacts(
      allowedNumbers: <num>{
        _round1(recent),
        _round1(prior),
        // The window itself, so "4 weeks" written in digits is not a lie.
        4,
        weeksRun,
      },
      allowedSeconds: <int>{
        if (recentPace != null) _paceSeconds(recentPace, unit),
        if (priorPace != null) _paceSeconds(priorPace, unit),
      },
    );
  }

  /// The reading as flat statements, for the model to phrase.
  static String _sheetFor({
    required String volume,
    required String against,
    required String direction,
    required int weeksRun,
    required double? recentPace,
    required double? priorPace,
    required UnitSystem unit,
  }) {
    final lines = <String>[
      'Last four weeks: $volume. The four weeks before that: $against. '
          'That is $direction.',
      'They ran in $weeksRun of the last 4 completed weeks.',
    ];
    if (recentPace != null &&
        priorPace != null &&
        (recentPace - priorPace).abs() >= 5) {
      final now = Pace.secondsPerKilometer(recentPace).format(unit);
      final before = Pace.secondsPerKilometer(priorPace).format(unit);
      lines.add(
        'Average pace now $now, before $before. They are '
        '${recentPace < priorPace ? 'quicker' : 'slower'}.',
      );
    }
    lines.add('No records were set. Do not say fastest, longest or best.');
    return lines.join('\n');
  }

  static double _round1(double v) => (v * 10).round() / 10;

  /// Pace in the unit it will be written in, as whole seconds.
  ///
  /// Per mile when the runner reads miles, because that is the number the model
  /// will write and therefore the one the validator has to recognise.
  static int _paceSeconds(double secondsPerKm, UnitSystem unit) {
    final pace = Pace.secondsPerKilometer(secondsPerKm);
    return switch (unit) {
      UnitSystem.metric => pace.secondsPerKilometer.round(),
      UnitSystem.imperial => pace.secondsPerMile.round(),
    };
  }

  /// Whether they are getting quicker, in their own numbers.
  ///
  /// Only over runs long enough for pace to mean something, and only when both
  /// windows have some — a comparison against nothing is not a comparison.
  /// Returns a leading space so it appends cleanly, or empty when there is
  /// nothing honest to say.
  static String _paceLine(
    List<RunSummary> recent,
    List<RunSummary> prior,
    UnitSystem unit,
  ) {
    final now = _averagePace(recent);
    final before = _averagePace(prior);
    if (now == null || before == null) return '';

    // Under five seconds a kilometre is inside the noise of a different route,
    // a different day and a different pair of shoes.
    if ((now - before).abs() < 5) return '';

    final quicker = now < before;
    final nowText = Pace.secondsPerKilometer(now).format(unit);
    final beforeText = Pace.secondsPerKilometer(before).format(unit);
    return quicker
        ? ' You are averaging $nowText against $beforeText, so you are getting '
              'quicker too.'
        : ' You are averaging $nowText against $beforeText, which is slower. '
              'Worth knowing if it was not the point.';
  }

  /// Distance-weighted average pace, so a long steady run counts for more than
  /// a short sharp one. Null when there is nothing long enough to judge.
  static double? _averagePace(List<RunSummary> runs) {
    var meters = 0.0;
    var seconds = 0.0;
    for (final run in runs) {
      if (run.distanceMeters < 1000) continue;
      meters += run.distanceMeters;
      seconds += run.duration.inSeconds;
    }
    if (meters <= 0 || seconds <= 0) return null;
    return seconds / (meters / 1000);
  }

  static double _totalMeters(List<RunSummary> runs) =>
      runs.fold<double>(0, (sum, r) => sum + r.distanceMeters);

  /// The runs between [from] and [to] days ago.
  static List<RunSummary> _within(
    List<RunSummary> sorted,
    DateTime today, {
    required int from,
    required int to,
  }) => sorted.where((r) {
    final age = daysBetweenDates(r.startedAt, today);
    return age >= to && age < from;
  }).toList();

  /// How many of the last [window] **completed** weeks contain at least one run.
  ///
  /// Weeks rather than run counts: a runner who did five runs in one week and
  /// nothing for three is not consistent, and a total would call them so.
  ///
  /// The week in progress is excluded rather than counted as a miss. Including
  /// it meant a runner opening the app on a Monday morning was marked down for
  /// not having run yet in a week that was six hours old.
  static int _weeksWithARun(
    List<RunSummary> sorted,
    DateTime today, {
    required int window,
  }) {
    final thisMonday = mondayOf(today);
    var weeks = 0;
    for (var i = 1; i <= window; i++) {
      final start = addDays(thisMonday, -7 * i);
      final end = addDays(start, 7);
      final ran = sorted.any(
        (r) => !r.startedAt.isBefore(start) && r.startedAt.isBefore(end),
      );
      if (ran) weeks++;
    }
    return weeks;
  }

  static String _consistencyLine(int weeksRun) => switch (weeksRun) {
    >= 4 => 'You have run in each of the last four weeks.',
    3 => 'Three of the last four weeks had a run in them.',
    2 => 'Two of the last four weeks had a run in them.',
    1 => 'One of the last four weeks had a run in it.',
    _ => 'None of the last four weeks had a run in them.',
  };
}

/// What the standing amounts to. Available for future styling; the design
/// language keeps them all monochrome for now (ADR-0009).
enum StandingVerdict {
  building,
  holding,
  easing,
  patchy,
  returning,
  gettingStarted,
  nothingYet,
}
