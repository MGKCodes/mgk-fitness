import 'package:mgk_units/mgk_units.dart';
import '../../recording/domain/run_summary.dart';
import 'pace_model.dart';
import 'runner_profile.dart';
import 'plan_history.dart';
import 'plan_shape.dart';
import 'readiness.dart';
import 'stored_plan.dart';
import 'training_plan.dart';

/// Turns what the app knows about a runner into **prose the coach reads**.
///
/// This is the product surface, not a serialiser. A model given
/// `{"availableWeekdays":[1,2,4,6,7],"soreness":[...]}` recites it — *"I see you
/// have soreness recorded on 26 July"* — because a struct in a prompt reads as a
/// record to be quoted, while a paragraph reads as knowledge to be used. Models
/// are trained overwhelmingly on prose; give them prose.
///
/// So the app stores typed state (the plan builder needs a `Set<int>`, not a
/// sentence) and renders it here. The model never sees the struct, so it cannot
/// quote one.
///
/// Two rules shape everything below.
///
/// **Say what changed, not what is true.** Re-establishing the whole picture
/// every turn is the loudest tell of a machine. A sore calf mentioned yesterday
/// is worth a line; the same line in message six is uncanny.
///
/// **Never put a number here the app cannot defend.** Everything rendered is
/// computed from stored runs and the validated plan. The model phrases; Dart
/// counts.
class CoachBrief {
  const CoachBrief._(this.text);

  /// The rendered brief, ready to drop into the system prompt.
  final String text;

  /// What to call them, as its own line. Empty where they never said, so the
  /// brief simply does not mention a name rather than inventing one.
  static String _calledLine(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return '';
    return 'The runner is called $trimmed. ';
  }

  @override
  String toString() => text;

  /// Writes the brief for a runner.
  ///
  /// [recentRuns] should be newest-first. [now] is injected so the relative
  /// dates ("yesterday", "three days ago") are testable.
  /// [name] is what the runner asked to be called, when they said. It leads the
  /// brief because a coach that has been told a name and does not use it is
  /// worse than one that never asked — and it is the only line here that is
  /// about the person rather than the training.
  factory CoachBrief.write({
    required List<RunSummary> recentRuns,
    StoredPlan? plan,
    RunnerProfile? profile,
    String? name,
    String? rollingSummary,
    List<LabelledPlan> history = const <LabelledPlan>[],
    UnitSystem unit = UnitSystem.metric,
    DateTime? now,
  }) {
    // Computed here rather than passed in, so every caller gets the same answer
    // and none of them can forget. Null for the shapes with nothing to be ready
    // for.
    final readiness = runnerProfileOf(plan, profile) == null
        ? null
        : assessReadiness(
            runnerProfileOf(plan, profile)!,
            recentRuns,
            now: now ?? DateTime.now(),
          );
    final today = now ?? DateTime.now();
    final runner = profile ?? plan?.profile;

    // First contact: nothing known at all. Said before anything else, because
    // "they have not logged any runs yet" on its own reads as a shrug rather
    // than as an opening.
    if (runner == null && plan == null && recentRuns.isEmpty) {
      final opening = rollingSummary?.trim();
      // The one exchange where a name matters most: this brief is what the
      // coach opens onboarding with, so without it the first thing it ever
      // says is addressed to nobody.
      final called = _calledLine(name);
      return CoachBrief._(
        opening == null || opening.isEmpty
            ? '${called}You have not coached this runner before and they have '
                  'not logged any runs yet. Find out what they want from their '
                  'running before suggesting anything.'
            : '${called}You have not coached this runner before and they have '
                  'not logged any runs yet.\n\n$opening',
      );
    }

    final paragraphs = <String>[];

    final called = _calledLine(name);
    if (called.isNotEmpty) paragraphs.add(called.trim());

    final training = _training(plan, runner, today, unit, readiness);
    if (training != null) paragraphs.add(training);

    final days = _availableDays(runner);
    if (days != null) paragraphs.add(days);

    // What they have tried before. Placed after the current block and before
    // the recent runs, because it is context for the plan rather than news: a
    // runner who has abandoned two marathon blocks at week nine is a different
    // runner to coach than one who has finished three, and the coach had no way
    // to know either.
    final past = planHistoryLine(
      history,
      distance: (m) => _distance(Distance.meters(m), unit),
    );
    if (past != null) paragraphs.add(past);

    final recent = _recent(recentRuns, today, unit);
    if (recent != null) paragraphs.add(recent);

    final fitness = _fitness(runner, unit);
    if (fitness != null) paragraphs.add(fitness);

    // The rolling summary goes last and in the runner's own terms — it carries
    // the things no schema holds: what they are anxious about, how they talk
    // about their training, what they have already tried.
    final summary = rollingSummary?.trim();
    if (summary != null && summary.isNotEmpty) paragraphs.add(summary);

    if (paragraphs.isEmpty) {
      return const CoachBrief._(
        'You have not coached this runner before and they have not logged any '
        'runs yet. Find out what they want from their running before '
        'suggesting anything.',
      );
    }
    return CoachBrief._(paragraphs.join('\n\n'));
  }

  /// What they are training for and where they are in it.
  static String? _training(
    StoredPlan? plan,
    RunnerProfile? profile,
    DateTime today,
    UnitSystem unit,
    Readiness? readiness,
  ) {
    if (plan == null) {
      if (profile == null) return null;
      final goalMeters = profile.goalDistanceMeters;
      if (goalMeters == null) return null;
      final goal = Distance.meters(goalMeters);
      return 'They are aiming at ${_distance(goal, unit)} but have no plan in '
          'place — they are logging runs and training by feel.';
    }

    final week = plan.weekIndexOn(today);
    final total = plan.skeleton.weeks.length;
    final slot = plan.weekOn(today);
    final volume = _distance(Distance.meters(slot.volumeMeters), unit);
    final goalMeters = plan.profile.goalDistanceMeters;
    final goal = goalMeters == null
        ? null
        : _distance(Distance.meters(goalMeters), unit);

    final phase = slot.isDeload
        ? 'a deload week'
        : '${_phaseWord(slot.phase)} week';

    // The shape decides the sentence, because the shapes are different training
    // situations and a coach told the wrong one gives the wrong advice. Telling
    // a parkrun regular they are "in week 3 of 12 of a block" would invent a
    // race, a taper and a deadline none of which exist.
    switch (shapeOf(plan.profile)) {
      case PlanShape.block:
        final days = daysBetweenDates(today, plan.profile.eventDate!);
        return 'They are in week $week of $total of a $goal block, $days days '
            'out from the event. This is $phase of about $volume.';

      case PlanShape.horizon:
        final assessment = readiness;
        final standing = assessment == null
            ? ''
            : assessment.isReady
            ? ' On the numbers they could cover the distance now — their long '
                  'run and their weekly volume are both where they need to be. '
                  'Tell them, and ask whether they want to find a race. That '
                  'decision is theirs, but they cannot make it without knowing.'
            : ' On the numbers they are ${assessment.summary}: they would want '
                  'a longest run around '
                  '${_distance(Distance.meters(assessment.longestNeededMeters), unit)} '
                  'and about '
                  '${_distance(Distance.meters(assessment.weeklyNeededMeters), unit)} '
                  'a week. Do not tell them they are ready before that.';
        return 'They are working toward being able to run $goal, with no race '
            'entered — so there is no date to plan back from and nothing to '
            'taper into. They are $week weeks in. This is $phase of about '
            '$volume.$standing';

      case PlanShape.rhythm:
        final commitments = plan.profile.commitments;
        final rhythm = commitments.isEmpty
            ? 'They run ${plan.profile.daysPerWeek} times a week'
            : 'They run ${plan.profile.daysPerWeek} times a week, including '
                  '${_commitmentPhrase(commitments, unit)}';
        return '$rhythm. There is no race and no block — the plan is to keep '
            'turning up, and about $volume a week is what that looks like. Do '
            'not push them toward a goal race unless they raise it; '
            'consistency is what they came for.';

      case PlanShape.log:
        return 'They have not told you what they are training for. They are '
            'logging runs. Find out what they want from their running before '
            'suggesting a plan.';
    }
  }

  /// "parkrun most Saturdays" — the commitments in the runner's own words.
  static String _commitmentPhrase(
    List<PlanCommitment> commitments,
    UnitSystem unit,
  ) {
    final parts = <String>[
      for (final c in commitments)
        <String>[
          c.label ?? 'a run',
          if (c.distanceMeters != null)
            'of ${_distance(Distance.meters(c.distanceMeters!), unit)}',
          'on ${_weekdayWord(c.weekday)}s',
          if (c.timed) '(they time it)',
        ].join(' '),
    ];
    if (parts.length == 1) return parts.single;
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  /// The days they said they could run, and the ones they said they could not.
  ///
  /// Here because of a change the coach agreed to and could not make. Asked to
  /// move a session to a Friday the runner had ruled out, it said *"I can
  /// certainly move that for you"* and produced a week with the session simply
  /// deleted — the validator refused the result, and the runner was told about
  /// a knock-on effect on their long run rather than about Friday.
  ///
  /// The model was not wrong so much as uninformed: nothing in the brief said
  /// which days were available, so the only way to find out was to propose
  /// something impossible and be refused. A constraint the coach is held to is
  /// a constraint the coach has to be told.
  ///
  /// Both halves are said. "They run Monday, Tuesday and Saturday" leaves the
  /// rest ambiguous between *cannot* and *not scheduled yet*, and it is the
  /// cannot that has to survive.
  static String? _availableDays(RunnerProfile? profile) {
    final available = profile?.availableWeekdays;
    if (available == null || available.isEmpty || available.length == 7) {
      return null; // nothing to warn about when every day is fair game
    }
    final free = available.toList()..sort();
    final busy = <int>[
      for (var d = 1; d <= 7; d++)
        if (!available.contains(d)) d,
    ];
    return 'They can run on ${_dayList(free)}. They have said they cannot run '
        'on ${_dayList(busy)}, so do not offer to move a session onto '
        '${busy.length == 1 ? 'that day' : 'those days'} — say plainly that it '
        'is not one of their days and ask which of theirs to use instead.';
  }

  /// "Monday, Tuesday and Saturday" — days in the runner's language.
  static String _dayList(List<int> weekdays) {
    final words = weekdays.map(_weekdayWord).toList();
    if (words.length == 1) return words.single;
    return '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}';
  }

  static String _weekdayWord(int weekday) => const <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][weekday - 1];

  /// What they have actually been doing. Relative dates, because "26 July"
  /// means nothing to a reader who does not know today's date.
  static String? _recent(
    List<RunSummary> runs,
    DateTime today,
    UnitSystem unit,
  ) {
    if (runs.isEmpty) {
      return 'They have not logged any runs yet.';
    }

    final latest = runs.first;
    final when = _relativeDay(latest.startedAt, today);
    final pace = _paceOf(latest);

    final lastWeek = runs
        .where((r) => today.difference(r.startedAt).inDays <= 7)
        .toList();
    final weekMeters = lastWeek.fold<double>(
      0,
      (sum, r) => sum + r.distanceMeters,
    );

    final sentences = <String>[
      'Their last run was $when: '
          '${_distance(Distance.meters(latest.distanceMeters), unit)}'
          '${pace == null ? '' : ' at ${pace.format(unit)}'}.',
      if (lastWeek.isEmpty)
        'They have not run in the past week.'
      else
        'Over the past seven days they have run ${lastWeek.length} '
            '${lastWeek.length == 1 ? 'time' : 'times'}, '
            '${_distance(Distance.meters(weekMeters), unit)} in total.',
    ];
    return sentences.join(' ');
  }

  /// What they are currently capable of, and what that projects to.
  ///
  /// Projections come from Riegel in Dart. The model must never estimate a race
  /// time itself — it would produce a plausible, confident, wrong number that
  /// the runner has no way to check.
  static String? _fitness(RunnerProfile? profile, UnitSystem unit) {
    final ttDistance = profile?.timeTrialDistanceMeters;
    final ttTime = profile?.timeTrialDuration;
    if (profile == null || ttDistance == null || ttTime == null) return null;

    final from = Distance.meters(ttDistance);
    final paces = TrainingPaces.fromRace(from, ttTime);

    final projections = <String>[
      for (final target in _projectionTargets)
        if ((target.meters - from.meters).abs() > 100)
          '${_distance(target, unit)} in about '
              '${_duration(riegelPredict(from, ttTime, target))}'
              '${_isAStretch(from, target) ? ' if the endurance is there' : ''}',
    ];

    return 'Their reference effort is ${_distance(from, unit)} in '
        '${_duration(ttTime)}, which puts easy running around '
        '${paces.easy.format(unit)} and threshold around '
        '${paces.threshold.format(unit)}. On that form the projections are '
        '${_list(projections)}.';
  }

  /// The phase as a word. Deliberately duplicated rather than imported from the
  /// presentation layer's `phaseLabel` — the domain must not depend on the UI,
  /// and the coach's phrasing ("a build week") is not the UI's ("Build").
  static String _phaseWord(Phase phase) => switch (phase) {
    Phase.base => 'a base',
    Phase.build => 'a build',
    Phase.peak => 'a peak',
    Phase.taper => 'a taper',
  };

  static const List<Distance> _projectionTargets = <Distance>[
    Distance.meters(5000),
    Distance.meters(10000),
    Distance.meters(21097.5),
    Distance.meters(42195),
  ];

  /// Riegel holds up to roughly four times the reference distance and gets
  /// optimistic well past that, so only a genuine stretch is flagged.
  ///
  /// The threshold is deliberately high. Caveating both the half *and* the
  /// marathon off a 5 km puts "if the endurance is there" twice in one sentence,
  /// which reads as a template rather than as a coach hedging one number.
  static bool _isAStretch(Distance from, Distance to) =>
      to.meters / from.meters >= 5;

  /// Distances the way a person writes them: "5 km", not "5.0 km". A trailing
  /// zero is a small thing that reads unmistakably machine-written.
  static String _distance(Distance d, UnitSystem unit) {
    final value = d.inDisplayUnit(unit);
    final rounded = value.roundToDouble();
    final whole = (value - rounded).abs() < 0.05 || value >= 10;
    return d.format(unit, fractionDigits: whole ? 0 : 1);
  }

  static String _duration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}'
          ':${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static Pace? _paceOf(RunSummary run) {
    if (run.avgPaceSecondsPerKm != null) {
      return Pace.secondsPerKilometer(run.avgPaceSecondsPerKm!);
    }
    if (run.distanceMeters <= 0) return null;
    return Pace.from(Distance.meters(run.distanceMeters), run.duration);
  }

  static String _relativeDay(DateTime at, DateTime today) {
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    return switch (days) {
      <= 0 => 'today',
      1 => 'yesterday',
      < 7 => '$days days ago',
      < 14 => 'a week ago',
      < 31 => '${(days / 7).round()} weeks ago',
      _ => '${(days / 30).round()} months ago',
    };
  }

  static String _list(List<String> items) => switch (items.length) {
    0 => 'not worth guessing at yet',
    1 => items.first,
    _ => '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}',
  };
}

/// The profile a brief is written against: the one passed in, or the one the
/// plan was built for.
RunnerProfile? runnerProfileOf(StoredPlan? plan, RunnerProfile? profile) =>
    profile ?? plan?.profile;
