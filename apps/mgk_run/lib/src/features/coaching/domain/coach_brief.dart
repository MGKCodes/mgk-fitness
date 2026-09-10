import 'package:mgk_units/mgk_units.dart';
import '../../recording/domain/run_summary.dart';
import 'coach_memory.dart';
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
/// **Never put a number here the app cannot defend.** Every figure rendered is
/// computed from stored runs and the validated plan. The model phrases; Dart
/// counts.
///
/// One section is deliberately not that, and is fenced off because of it. The
/// recollections paragraph carries the runner's own past words, which are
/// evidence rather than fact — they are rendered dated, attributed, and under a
/// sentence saying they are not the current picture. A number that appears
/// there is something the runner once said, never something the app is standing
/// behind, and the paragraph tells the coach so.
class CoachBrief {
  const CoachBrief._(this.text);

  /// The rendered brief, ready to drop into the system prompt.
  final String text;

  // **The runner's name is deliberately absent from this file, and there is no
  // parameter to pass one.**
  //
  // There was: `_calledLine(name)` rendered `The runner is called <name>.` and
  // led the brief, on the reasoning that a coach told a name and not using it
  // is worse than one that never asked. That reasoning is fine and it was
  // overruled by a sentence we had already published.
  //
  // `docs/privacy-policy.md`, live at mgkfitness.mgkcodes.com/run/privacy and
  // pinned by CI, says without qualification:
  //
  // > We never send your **name, email, or account identifier**
  //
  // `legal_copy.dart` says the same thing to the runner in Settings. The brief
  // goes into the system prompt verbatim (`surfaces.ts`), so every coach turn
  // made that sentence false, for a first name the runner gave at sign-up.
  //
  // **Removed rather than made conditional, and the parameter removed with
  // it.** A `name` argument that must never be supplied is a loaded gun: the
  // next person to want a warmer opener passes it, analyze stays green, tests
  // stay green, and a published privacy promise breaks silently. The only way
  // to make the guarantee structural is for there to be nothing to pass.
  //
  // **What this does NOT cover**, and is worth knowing before anyone claims
  // the policy is now true end to end:
  //
  //   * The last twenty conversation turns go verbatim, so a runner who types
  //     their own name has sent it. The policy discloses that explicitly —
  //     "your last twenty messages, as you wrote them" — so it is disclosed
  //     rather than contradicted.
  //   * `rollingSummary` is model-written prose from earlier turns. Summaries
  //     written BEFORE this change may contain a name, and they persist in
  //     `coach.summaries` and are re-sent on every turn. Code cannot undo
  //     that; it needs a decision about existing rows.
  //
  // If a name is ever wanted here again, the policy and `legal_copy.dart` have
  // to change first — in that order, and with the site redeployed, because the
  // published page is the artefact CI pins.

  @override
  String toString() => text;

  /// Writes the brief for a runner.
  ///
  /// [recentRuns] should be newest-first. [now] is injected so the relative
  /// dates ("yesterday", "three days ago") are testable.
  /// [recalled] is the on-demand tier of the coach's memory: a few turns from
  /// past conversations that matched what is being asked now. They are rendered
  /// **dated and attributed**, never as facts — see [_recollections].
  factory CoachBrief.write({
    required List<RunSummary> recentRuns,
    StoredPlan? plan,
    RunnerProfile? profile,
    String? rollingSummary,
    List<LabelledPlan> history = const <LabelledPlan>[],
    List<CoachTurn> recalled = const <CoachTurn>[],
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
      final first = <String>[
        opening == null || opening.isEmpty
            ? 'You have not coached this runner before and they have '
                  'not logged any runs yet. Find out what they want from their '
                  'running before suggesting anything.'
            : 'You have not coached this runner before and they have '
                  'not logged any runs yet.\n\n$opening',
        // The refusal goes in even here, where there is least to invent. It is
        // the *first* conversation that is most likely to be asked "what did I
        // run last week", and least likely to have an answer.
        _emptyLogRefusal,
      ];
      final remembered = _recollections(recalled, today);
      if (remembered != null) first.add(remembered);
      return CoachBrief._(first.join('\n\n'));
    }

    final paragraphs = <String>[];

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

    // Recall goes after everything the app can prove, because it is the one
    // section that is *not* proof. Anything it carries is something the runner
    // said once, and the paragraph says so at length.
    final remembered = _recollections(recalled, today);
    if (remembered != null) paragraphs.add(remembered);

    if (paragraphs.isEmpty) {
      return const CoachBrief._(
        'You have not coached this runner before and they have not logged any '
        'runs yet. Find out what they want from their running before '
        'suggesting anything.\n\n$_emptyLogRefusal',
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
        // **Race day is not "-2 days out from the event".** The countdown
        // reads perfectly well until it goes negative, at which point it is
        // arithmetic rather than a sentence, and a coach handed it will
        // cheerfully tell somebody their marathon is in minus two days. The
        // three cases below are the three things a block can be doing, and the
        // last one is the coach's cue to ask a question the app cannot answer
        // for itself.
        final where = switch (days) {
          0 =>
            'Today is race day. There is nothing left to coach — wish them '
                'well, keep it short, and answer what they ask.',
          < 0 =>
            'Race day was ${-days} ${days == -1 ? 'day' : 'days'} ago and they '
                'have not told you how it went. Ask, once, and let them answer '
                'before you say anything about what comes next.',
          _ => 'They are $days days out from the event.',
        };
        return 'They are in week $week of $total of a $goal block. $where '
            'This is $phase of about $volume.';

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
  ///
  /// **Every run named here carries its own date**, and the runs before the
  /// latest are named rather than only counted. That is the second half of the
  /// fix for the first field test's answer: asked to look at a previous run,
  /// the coach described one from a week earlier as "yesterday". Sessions stop
  /// week-old conversation being in front of the model at all; dating each run
  /// means that even when a recollection does surface, there is a dated log
  /// beside it to be checked against.
  static String? _recent(
    List<RunSummary> runs,
    DateTime today,
    UnitSystem unit,
  ) {
    if (runs.isEmpty) {
      return 'They have not logged any runs yet. $_emptyLogRefusal';
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

    // The handful before the latest, each dated. Bounded at four: this is the
    // "say what changed" section, and a runner's whole log recited back is the
    // record-in-a-prompt failure the class doc opens with.
    final earlier = <String>[
      for (final r in runs.skip(1).take(4))
        '${_distance(Distance.meters(r.distanceMeters), unit)} '
            '${_relativeDay(r.startedAt, today)}',
    ];

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
      if (earlier.isNotEmpty) 'Before that, ${_list(earlier)}.',
      // Deliberately "their most recent runs" rather than "the runs in their
      // log": this section shows at most five, and telling the coach it has the
      // whole log would have it assure a runner of forty runs that they have
      // done five. The claim being made is about the dates, which are exact.
      'Those are their most recent runs, and the dates are as given. Do not '
          'describe a run as more recent than its date here.',
    ];
    return sentences.join(' ');
  }

  /// What the coach must do when the log is empty and it is asked about a run.
  ///
  /// The failure this refuses is confabulation, and it is not hypothetical in
  /// spirit even though the field test's version of it was a true memory: with
  /// nothing to report, a model asked about "my previous run" will produce a
  /// plausible one. The instruction names the specific way a run can seem to
  /// exist without being in the log — it was mentioned in a conversation and
  /// never logged — because that is the case where declining feels wrong to the
  /// model and is nonetheless right.
  static const String _emptyLogRefusal =
      'If they ask about a run, say there is nothing in their log rather than '
      'describing one. A run they mentioned to you in conversation was never '
      'logged, and you must not report it as though it were.';

  /// The on-demand tier of the coach's memory: a few things the runner said in
  /// past conversations that matched what they are asking now.
  ///
  /// **Every line is dated, and the paragraph says what it is before it says
  /// any of it.** That ordering is the whole design. The bug this section
  /// exists to avoid is the one that produced it: undated past conversation
  /// sitting in the context reads as current, and the coach placed a week-old
  /// run "yesterday". Retrieval without a date is the same bug with fewer
  /// tokens.
  ///
  /// It is bounded by count rather than by length. The words are the runner's
  /// own and truncating them mid-sentence can change what they said, which is
  /// a worse failure than a slightly longer prompt; `recollectionsFrom` keeps
  /// the count at four.
  static String? _recollections(List<CoachTurn> turns, DateTime today) {
    if (turns.isEmpty) return null;

    final lines = <String>[
      for (final turn in turns)
        '${_relativeDay(turn.at, today)}, they said: ${_oneLine(turn.text)}',
    ];
    return 'Some things they have said to you before, each with when they said '
        'it. These are recollections of past conversations, not facts about '
        'their training — what is true now is above, in their plan and their '
        'log. Anything mentioned here happened on the date given and not more '
        'recently, and a run named in one of these lines is only a run they '
        'did if their log says so.\n\n${lines.join('\n')}';
  }

  /// One line of a stored turn. Whitespace is collapsed so a message the runner
  /// typed across three lines does not break the list it is rendered into.
  static String _oneLine(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');

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
