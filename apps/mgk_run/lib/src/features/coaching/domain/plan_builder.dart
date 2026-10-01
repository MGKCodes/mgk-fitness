import 'dart:math' as math;

import 'plan_shape.dart';
import 'prescribed_distance.dart';
import 'race_day.dart';
import 'runner_profile.dart';
import 'stored_plan.dart';
import 'training_plan.dart';
import 'week_progress.dart';

/// Deterministic plan construction — the non-LLM path. Two uses (both from
/// docs/architecture/plan-generation.md):
///  - the **fallback** when LLM generation fails twice, so a runner always has
///    a structurally sound plan; and
///  - a way to stand up and verify the plan UI with no model in the loop.
///
/// Everything here is built to pass the [validateSkeleton] / [validateWeek]
/// invariants *by construction* — the validator is the oracle the matrix tests
/// check it against.

/// Builds a skeleton (the arc) from the runner's profile. Volume starts at the
/// runner's current weekly volume, ramps under the cap, deloads on cadence, and
/// tapers into the event. Length comes from the weeks until the event unless
/// [weeks] is given.
PlanSkeleton buildSkeleton(
  RunnerProfile profile, {
  required DateTime now,
  int? weeks,
}) {
  final shape = shapeOf(profile);

  // Calendar days, not elapsed ones. `difference(now).inDays` truncates the
  // part-day between "now" and midnight on race day, so the same runner with
  // the same race got a 16-week block at 01:00 and a 15-week block at 09:00 —
  // a week of training decided by when they happened to tap the button.
  //
  // Only a block counts backwards from a date. A horizon has no date to count
  // from, so it runs a default arc and simply keeps going; a rhythm is not
  // building toward anything at all.
  final natural = switch (shape) {
    PlanShape.block => (daysBetweenDates(now, profile.eventDate!) / 7).floor(),
    PlanShape.horizon => _horizonWeeks,
    PlanShape.rhythm || PlanShape.log => _rhythmWeeks,
  };
  final total = (weeks ?? natural).clamp(kMinPlanWeeks, _maxWeeks);

  // A rhythm holds a level rather than climbing to one: every week is the
  // volume the runner already runs, and the deloads and taper that shape a
  // block would be inventing a peak nobody is training for.
  if (!shape.progresses) {
    return PlanSkeleton(
      weeks: <SkeletonWeek>[
        for (var i = 0; i < total; i++)
          SkeletonWeek(
            index: i + 1,
            phase: Phase.base,
            volumeMeters: profile.currentWeeklyMeters,
            longRunMeters: _longRun(profile.currentWeeklyMeters),
          ),
      ],
    );
  }

  // A horizon has nothing to taper into — a taper without a date is a guess
  // about a race that has not been entered.
  final taperWeeks = !shape.tapers ? 0 : (total >= 10 ? 2 : 1);
  final nonTaper = total - taperWeeks;

  final phases = _phases(total, taperWeeks);
  final deloads = _deloads(total, taperWeeks);

  final volumes = List<double>.filled(total, 0);
  final longRuns = List<double>.filled(total, 0);

  var lastNormal = profile.currentWeeklyMeters; // the non-deload trajectory
  var peak = profile.currentWeeklyMeters; // running max of normal weeks
  volumes[0] = profile.currentWeeklyMeters;
  longRuns[0] = _longRun(volumes[0]);

  for (var i = 1; i < total; i++) {
    final week = i + 1; // 1-based
    double v;
    if (phases[i] == Phase.taper) {
      final tIdx = week - nonTaper; // 1..taperWeeks
      final factor = taperWeeks == 1 ? 0.65 : (tIdx == 1 ? 0.75 : 0.60);
      v = peak * factor;
    } else if (deloads[i]) {
      v = volumes[i - 1] * 0.70;
    } else if (deloads[i - 1]) {
      // First week back from a deload may jump to the trajectory (the validator
      // waives the ramp cap here).
      v = lastNormal * 1.05;
      lastNormal = v;
      peak = math.max(peak, v);
    } else {
      v = volumes[i - 1] * 1.08; // under the 10% cap
      lastNormal = v;
      peak = math.max(peak, v);
    }
    volumes[i] = v;
    longRuns[i] = _longRun(v);
  }

  return PlanSkeleton(
    weeks: <SkeletonWeek>[
      for (var i = 0; i < total; i++)
        SkeletonWeek(
          index: i + 1,
          phase: phases[i],
          volumeMeters: volumes[i],
          longRunMeters: longRuns[i],
          isDeload: deloads[i],
        ),
    ],
  );
}

/// Fills a single week deterministically from its skeleton [slot] — the
/// "provisional" fallback after two failed generations (plan-generation.md):
/// one long run, one workout (unless deloading), the rest easy, on the runner's
/// available days. Built to satisfy [validateWeek] by construction for a
/// realistic profile (three or more training days).
/// [unusableWeekdays] are days this particular week cannot use even though the
/// runner is generally available on them: days already gone in the current
/// week, and race day in the final one. **The builder is told which days,
/// never which dates** -- the plan model carries no dates by design, and the
/// caller that owns the calendar ([PlanRepository]) is the one that can work
/// them out. Ignored when it would leave nothing to train on, because a week
/// with one session is a better answer than a crash.
TrainingWeek buildFallbackWeek(
  SkeletonWeek slot,
  RunnerProfile profile, {
  Set<int> unusableWeekdays = const <int>{},
}) {
  if (shapeOf(profile) == PlanShape.rhythm) {
    return _buildRhythmWeek(slot, profile);
  }
  final usable = profile.availableWeekdays
      .where((d) => !unusableWeekdays.contains(d))
      .toList();
  final available =
      (usable.isEmpty ? profile.availableWeekdays.toList() : usable)..sort();
  final n = profile.daysPerWeek.clamp(1, available.length);
  final days = _spread(available, n);

  final sessions = <PlannedSession>[
    // The long run is the slot's own declared long run, not a fresh
    // calculation. The plan arc already shows the slot's number, so deriving it
    // again here let the arc and the week disagree about the same session.
    // Rounding it to the prescribed grid does not bring that back: the arc shows
    // whole kilometres too, so both screens still say 19 km — what they can no
    // longer do is start from two different numbers.
    ..._fillDays(
      days,
      total: slot.volumeMeters,
      longRun: slot.longRunMeters,
      isDeload: slot.isDeload,
    ),
    for (final day in _strengthDays(
      available,
      days,
      profile.strengthDaysPerWeek,
    ))
      PlannedSession(weekday: day, kind: SessionKind.strength),
  ];

  return TrainingWeek(
    skeletonIndex: slot.index,
    sessions: sessions,
    provisional: true,
  );
}

/// The week the race is in, for a plan aimed at a date.
///
/// **A rule, not a proposal.** Every other week is a shape the model may
/// improve on. This one has a right answer that does not depend on the runner,
/// so it is written here and the model is never asked (ADR-0044).
///
/// It was not a week of its own before. Race day was only a day the builder
/// was told to avoid, so the week kept everything else an ordinary one has:
/// the quality session on its first day, and its long run on the last day left
/// free, which for a Sunday race is the Saturday. A runner three days out was
/// being asked for a threshold run and a long run, and then to race.
///
/// What race week is instead:
///
/// - **Race day is the race**, and carries no session. The screens draw it
///   from the profile.
/// - **The day before is rest.**
/// - **No long run and nothing hard.** Easy running only: nothing done this
///   week makes the runner fitter by Sunday, and plenty can make them tired.
/// - **Each run is shorter than the one before**, so the week arrives at the
///   race rather than stopping short of it.
/// - **One fewer running day than usual**, because the race is one of them.
///
/// The distance comes from the slot: what the taper week held outside its long
/// run. The plan arc's number for the week is therefore still the week's
/// running before the race, less the long run the race replaces.
///
/// A race on a Monday or a Tuesday leaves nothing ahead of it in its own week,
/// and the week is then empty, which is right.
TrainingWeek buildRaceWeek(
  SkeletonWeek slot,
  RunnerProfile profile, {
  required int raceWeekday,
}) {
  final int eve = raceWeekday - 1;
  final before = <int>[
    for (final d in profile.availableWeekdays)
      if (d < eve) d,
  ]..sort();
  final n = math.min(profile.daysPerWeek - 1, before.length);
  if (n <= 0) {
    return TrainingWeek(skeletonIndex: slot.index, sessions: const []);
  }
  final days = _spread(before, n);

  final double budget = slot.beforeRaceMeters;
  // n, n-1, ... 1: the first run of the week is the longest it will get.
  final int weights = n * (n + 1) ~/ 2;
  final double cap = roundPrescribed(slot.longRunMeters);
  final shares = <double>[
    for (final m in prescribeAcross(<double>[
      for (var k = 0; k < n; k++) budget * (n - k) / weights,
    ]))
      cap > 0 ? math.min(m, cap) : m,
  ];

  return TrainingWeek(
    skeletonIndex: slot.index,
    sessions: <PlannedSession>[
      for (var k = 0; k < n; k++)
        PlannedSession(
          weekday: days[k],
          kind: SessionKind.easy,
          distanceMeters: shares[k],
        ),
    ],
  );
}

/// [slot] as Dart would fill it, for a week nothing has been stored for yet.
///
/// What the calendar draws beyond the planning horizon. It asked
/// [buildFallbackWeek] directly, which knows no dates, so the last pane of
/// every calendar showed the long run on race day until that week was
/// materialised, sixteen weeks later.
TrainingWeek draftWeekFor(StoredPlan plan, SkeletonWeek slot) {
  final int? raceWeekday = raceWeekdayIn(plan, slot);
  return raceWeekday == null
      ? buildFallbackWeek(slot, plan.profile)
      : buildRaceWeek(slot, plan.profile, raceWeekday: raceWeekday);
}

/// Whether [week] can stand as the week of a race on [raceWeekday]: nothing
/// on the day itself, and no long run anywhere in it.
///
/// What a week stored before race week had a shape fails, and what
/// [PlanRepository] rebuilds when it does.
///
/// **Deliberately the same two things `validateWeek` refuses of an adjustment
/// in race week, and no more.** [buildRaceWeek] is stricter than this: it also
/// rests the day before and keeps everything easy. But a runner who asks the
/// coach for a short run the day before their race has asked for something
/// reasonable, and a test stricter than the validator would quietly undo it
/// the next time the week was read.
bool isRaceWeekShaped(TrainingWeek week, {required int raceWeekday}) {
  for (final s in week.sessions) {
    if (s.kind == SessionKind.rest) continue;
    if (s.weekday == raceWeekday) return false;
    if (s.kind == SessionKind.long) return false;
  }
  return true;
}

/// Shares [total] metres over [days], making the last of them the long run when
/// [longRun] is positive and shaping the rest around it.
///
/// Lifted out of [buildFallbackWeek] so [refitWeek] can use the same arithmetic
/// rather than forming a second opinion about what a training week looks like.
/// Two builders shaping weeks differently is how a runner ends up with a
/// rebalanced week that does not resemble the plan it came from.
///
/// The share table is arithmetic, not a prescription: it hands back 4,137 m for
/// a Tuesday because that is what 40 km divided by a shape comes to. This is
/// where it becomes something a coach would say out loud — at the session,
/// rather than at the arc, because the arc is the plan's working and the session
/// is what the runner is asked to run.
///
/// The long run and the rest go on the grid by different routes, and
/// deliberately.
///
/// The long run is rounded on its own, because it has to keep matching the
/// number the plan arc shows for the same week and rounding moves it by at most
/// half a kilometre. Apportioning it with the others was tried and is worse: it
/// can move a full kilometre, and the arc and the week start disagreeing again —
/// the exact bug taking the slot's own long run exists to prevent.
///
/// The rest are *apportioned*, because rounding them one at a time throws the
/// week away: seven days of 1.14 km each fall to 1 km apiece and an 8 km week
/// arrives as 7. Then capped at the long run, because two roundings going
/// opposite ways can otherwise hand a Tuesday more kilometres than the long run
/// kept — 2.5 km rounding up to 3 past a 2.4 km long run rounding down to 2.
/// Capping can leave the week a kilometre short of the arc, which is inside what
/// the validator allows and is the lesser of the two wrongs.
///
/// A zero [longRun] means the week has no long run to place — the refit's case,
/// where the runner has already been out and done it. The cap goes with it: a
/// cap at zero would round the whole week away to nothing.
List<PlannedSession> _fillDays(
  List<int> days, {
  required double total,
  required double longRun,
  required bool isDeload,
}) {
  if (days.isEmpty) return const <PlannedSession>[];
  final n = days.length;
  final hasLong = longRun > 0;
  final others = hasLong ? n - 1 : n;
  final remainder = hasLong ? total - longRun : total;
  final shape = _fitUnderLongRun(
    _weekShape(others, isDeload: isDeload),
    remainder: remainder,
    longRun: longRun,
  );

  final longGridded = roundPrescribed(longRun);
  final shares = <double>[
    for (final m in prescribeAcross(<double>[
      for (var k = 0; k < others; k++) remainder * shape[k].share,
    ]))
      hasLong ? math.min(m, longGridded) : m,
  ];
  return <PlannedSession>[
    for (var k = 0; k < others; k++)
      PlannedSession(
        weekday: days[k],
        kind: shape[k].kind,
        distanceMeters: shares[k],
      ),
    if (hasLong)
      PlannedSession(
        weekday: days[n - 1],
        kind: SessionKind.long,
        distanceMeters: longGridded,
      ),
  ];
}

/// Refits what is **left** of [week] around what has already happened in it.
///
/// The deterministic half of "adjust my week", and the answer to the complaint
/// that named it: the coach "just reshuffles the week generically" when a run
/// lands on a rest day instead of noticing the run and fitting around it. The
/// model does this properly when it is reachable and told what happened;
/// [AdaptationService] reaches for this when it is not, so a runner whose
/// provider is down still gets a week that has looked at their log.
///
/// Three rules, and they are the whole of it.
///
/// **1. A day that has been run is settled.** Whatever the week prescribed on it
/// stays exactly as it was — the session happened, and a plan that quietly moved
/// or resized it afterwards would be rewriting the runner's own week under them.
/// The validator holds the same line as `session_already_done`; this builder
/// simply cannot break it, which is the point of the two agreeing.
///
/// **2. A refit never asks for more than the week already asked for.** The
/// budget for what remains is the smaller of two numbers: what the plan still
/// had ahead of it, and what is left of the slot's target once everything
/// already run is counted. Both matter and neither alone is enough.
///
/// The first stops missed distance being piled onto the weekend. A coach does
/// not make you run Tuesday on top of Sunday, and the arithmetic answer — "you
/// owe 42 km and have two days" — is how a runner who missed two sessions gets
/// handed a 36 km weekend. Missed work is written off, with one exception: a
/// missed *long run* is carried, because missing an easy run is a Tuesday that
/// got away and missing the long run is a week that did not happen
/// ([MissedSession.isKey] draws the same line about the same week).
///
/// The second is the case the runner actually complained about. An unplanned
/// Wednesday is training already banked, so it is credited by asking for *less*
/// from the days that are left, not by pretending it did not happen. Counted
/// against the **slot** rather than the week, so refitting twice cannot ratchet
/// the target down each time.
///
/// **3. Days that have gone are not scheduled.** Only today and later, only days
/// the runner said they are free, and never a day already run. Today is fair
/// game: the evening is still theirs.
TrainingWeek refitWeek({
  required TrainingWeek week,
  required SkeletonWeek slot,
  required RunnerProfile profile,
  required WeekAsRun soFar,
}) {
  final settled = soFar.settledWeekdays;

  // Everything on a settled day survives verbatim — the run, and any strength
  // work sharing the day with it.
  final kept = <PlannedSession>[
    for (final s in week.sessions)
      if (settled.contains(s.weekday)) s,
  ];

  // Strength still ahead survives too. The runner is rebalancing their
  // *running*, and re-placing gym days they did not ask about is the generic
  // reshuffle this exists to stop. Strength on a day that has gone goes with the
  // runs on it: it cannot be done now.
  final keptStrength = <PlannedSession>[
    for (final s in week.support)
      if (!settled.contains(s.weekday) && !_hasPassed(soFar, s.weekday)) s,
  ];

  // The days a refit may use. Already in weekday order, because [soFar] is.
  final open = <int>[
    for (final d in soFar.days)
      if (!d.hasPassed &&
          d.ranMeters == 0 &&
          profile.availableWeekdays.contains(d.weekday))
        d.weekday,
  ];

  // A day already run has been spent, prescribed or not. An unplanned Wednesday
  // used one of the days the runner told us they could train, and prescribing as
  // though it had not is how someone who said five days ends the week having
  // been asked for six.
  final n = (profile.daysPerWeek - settled.length).clamp(0, open.length);

  final longDay = _longRunDay(soFar);
  // Owed unless it has been run, or waved off. A skipped long run is the
  // runner's decision, and re-prescribing it would be the plan overruling them.
  final longOwed = longDay != null && !longDay.isDone && !longDay.isSkipped;
  final rescued = longDay != null && longDay.isMissed
      ? longDay.prescribed!.distanceMeters
      : 0.0;

  final budget = math.max(
    0.0,
    math.min(
      soFar.remainingMeters + rescued,
      slot.volumeMeters - soFar.ranMeters,
    ),
  );

  final fresh = n == 0 || budget <= 0
      ? const <PlannedSession>[]
      : _fillDays(
          _spread(open, n),
          total: budget,
          longRun: longOwed ? _refitLongRun(slot, budget: budget, days: n) : 0,
          isDeload: slot.isDeload,
        );

  return TrainingWeek(
    skeletonIndex: week.skeletonIndex,
    sessions: <PlannedSession>[
      ...kept,
      ...keptStrength,
      ..._easeBeside(fresh, kept),
    ]..sort((a, b) => a.weekday.compareTo(b.weekday)),
    // Deterministic, not generated — the same claim [buildFallbackWeek] makes,
    // and for the same reason: the runner should be able to see that no model
    // wrote this and ask for it again when one is reachable.
    provisional: true,
  );
}

/// The long run, sized to the days that are actually left.
///
/// [SkeletonWeek.longRunMeters] is what the week wanted, and it gets it whenever
/// the budget can carry it — the plan arc shows that number, and a refit that
/// derived its own would put the arc and the week back to disagreeing about the
/// same session. The ceiling is the only thing that overrules it: a kilometre is
/// left for every other day, so nothing is prescribed at zero and nothing rounds
/// away to it.
///
/// Deliberately no floor. Squeezing the long run toward the average day when the
/// budget is tight was tried and it walks straight into the 40% share rule — a
/// long run pushed *up* to half of a two-day remainder is the lopsided week that
/// rule exists to catch. The other days are already held under the long run by
/// [_fillDays], so a tie is the worst this can produce, and a tie is harmless:
/// the long run is the session whose kind says so, never the biggest number in
/// the week.
double _refitLongRun(
  SkeletonWeek slot, {
  required double budget,
  required int days,
}) => math.min(slot.longRunMeters, math.max(1000, budget - (days - 1) * 1000));

/// The day this week's long run was prescribed on, and what became of it.
DayAsRun? _longRunDay(WeekAsRun soFar) {
  for (final d in soFar.days) {
    if (d.prescribed?.kind == SessionKind.long) return d;
  }
  return null;
}

bool _hasPassed(WeekAsRun soFar, int weekday) =>
    soFar.days.any((d) => d.weekday == weekday && d.hasPassed);

/// Softens a new quality session that would land beside one already run.
///
/// The kept days are history and cannot move, so the new session is the one that
/// gives way. It is downgraded rather than shuffled: the shape's ordering is
/// what puts the recovery run after the quality session and the gentle day
/// before the long run, and reordering the week to dodge one adjacency costs all
/// of that to fix a single day.
List<PlannedSession> _easeBeside(
  List<PlannedSession> fresh,
  List<PlannedSession> kept,
) {
  final hardKept = <int>{
    for (final s in kept)
      if (s.kind.isHard) s.weekday,
  };
  if (hardKept.isEmpty) return fresh;
  return <PlannedSession>[
    for (final s in fresh)
      if (s.kind.isHard &&
          (hardKept.contains(s.weekday - 1) ||
              hardKept.contains(s.weekday + 1)))
        PlannedSession(
          weekday: s.weekday,
          kind: SessionKind.easy,
          distanceMeters: s.distanceMeters,
        )
      else
        s,
  ];
}

/// A rhythm week: the commitments they made, plus easy runs to fill out the
/// days they said they run.
///
/// **The commitment is the plan, not a suggestion to work around.** parkrun is
/// on Saturday at 5 km because that is what parkrun is; a builder that shuffled
/// it to balance the week would have missed the point of a rhythm entirely. The
/// filler runs move around it, never the other way.
TrainingWeek _buildRhythmWeek(SkeletonWeek slot, RunnerProfile profile) {
  final available = profile.availableWeekdays.toList()..sort();
  final committed = <int, PlannedSession>{};

  for (final c in profile.commitments) {
    // A commitment with no distance is still a run — the runner said they turn
    // up, not how far. The week's share gives it a length.
    committed[c.weekday] = PlannedSession(
      weekday: c.weekday,
      // Timed and repeated is a time trial, not a threshold session — nobody
      // runs their parkrun at an effort they could hold for an hour.
      kind: c.timed ? SessionKind.timeTrial : SessionKind.easy,
      distanceMeters: c.distanceMeters ?? 0,
      label: c.label,
    );
  }

  final target = profile.daysPerWeek.clamp(1, 7);
  final fillDays = <int>[
    for (final d in available)
      if (!committed.containsKey(d)) d,
  ];
  final fillCount = (target - committed.length).clamp(0, fillDays.length);
  final chosen = _spread(fillDays, fillCount);

  // Whatever the commitments do not account for is shared between the filler
  // runs. A runner whose commitments already exceed the week runs those and
  // nothing else — their word beats the arithmetic.
  final committedMeters = committed.values.fold<double>(
    0,
    (sum, s) => sum + s.distanceMeters,
  );
  final remainder = (slot.volumeMeters - committedMeters).clamp(
    0.0,
    double.infinity,
  );
  final perFill = chosen.isEmpty ? 0.0 : remainder / chosen.length;
  final fill = _rhythmFill(chosen, committed.keys, remainder);

  // The filler runs go on the grid; the commitments do not. A commitment's
  // distance is the runner's own number — parkrun is 5 km because parkrun is
  // 5 km — and putting their word on our grid would be the plan correcting them
  // about something they told us.
  //
  // Apportioned across the fillers together, so what the commitments left over
  // is still what gets run. Rounding each one alone would lose a kilometre here
  // and a kilometre there out of the only part of the week the plan controls.
  final filledDays = fill.keys.toList(growable: false);
  final fillDistances = prescribeAcross(<double>[
    for (final day in filledDays) fill[day]!.meters,
  ]);
  final sessions = <PlannedSession>[
    ...committed.values,
    for (var i = 0; i < filledDays.length; i++)
      PlannedSession(
        weekday: filledDays[i],
        kind: fill[filledDays[i]]!.kind,
        distanceMeters: fillDistances[i],
      ),
    for (final day in _strengthDays(
      available,
      <int>[...committed.keys, ...chosen]..sort(),
      profile.strengthDaysPerWeek,
    ))
      PlannedSession(weekday: day, kind: SessionKind.strength),
  ]..sort((a, b) => a.weekday.compareTo(b.weekday));

  // A commitment with no stated distance would otherwise sit at zero. Give it
  // the same share as a filler run, so the week adds up and the row is not a
  // session with no length.
  final filled = <PlannedSession>[
    for (final s in sessions)
      if (s.kind.isRun && s.distanceMeters <= 0)
        PlannedSession(
          weekday: s.weekday,
          kind: s.kind,
          // A length the plan invented, so it is prescribed on the grid like
          // any other — the runner did not name this number, we did.
          distanceMeters: roundPrescribed(
            perFill > 0 ? perFill : slot.volumeMeters / target,
          ),
          label: s.label,
        )
      else
        s,
  ];

  return TrainingWeek(
    skeletonIndex: slot.index,
    sessions: filled,
    provisional: true,
  );
}

/// The runs that fill a rhythm week around its commitments.
///
/// **Not an even split.** The flatness that made a block week read as "a number
/// divided by four" came back here by a different route: one commitment and two
/// free days gave a parkrun runner 7 km and 7 km. A week has a shape whether or
/// not it is building toward anything.
///
/// The shape here is simpler than a block's, because a rhythm has no long run
/// and its quality session is the commitment. What is left is a longer aerobic
/// run and a shorter one — and the shorter one goes **nearest the commitment**,
/// so the runner arrives at the thing they measure themselves by with fresher
/// legs than they left it with.
Map<int, ({SessionKind kind, double meters})> _rhythmFill(
  List<int> days,
  Iterable<int> commitmentDays,
  double remainder,
) {
  if (days.isEmpty || remainder <= 0) {
    return <int, ({SessionKind kind, double meters})>{};
  }

  // Shares from longest to shortest. One free day takes the lot; beyond that
  // the week tapers toward the commitment.
  const shares = <int, List<double>>{
    1: <double>[1.00],
    2: <double>[0.58, 0.42],
    3: <double>[0.40, 0.34, 0.26],
    4: <double>[0.31, 0.27, 0.23, 0.19],
    5: <double>[0.26, 0.23, 0.20, 0.17, 0.14],
    6: <double>[0.22, 0.20, 0.18, 0.15, 0.13, 0.12],
  };
  final weights =
      shares[days.length] ??
      <double>[for (var i = 0; i < days.length; i++) 1 / days.length];

  // Furthest from a commitment first, so the largest share lands where there is
  // most room around it.
  int gap(int day) => commitmentDays.isEmpty
      ? 0
      : commitmentDays
            .map((c) => _weekdayGap(day, c))
            .reduce((a, b) => a < b ? a : b);
  final ordered = <int>[...days]
    ..sort((a, b) {
      final byGap = gap(b).compareTo(gap(a));
      return byGap != 0 ? byGap : a.compareTo(b);
    });

  final out = <int, ({SessionKind kind, double meters})>{};
  for (var i = 0; i < ordered.length; i++) {
    out[ordered[i]] = (
      // The shortest run of a rhythm week is a recovery run, for the same
      // reason it is in a block: it is the day after something that cost them.
      kind: i == ordered.length - 1 && ordered.length > 1
          ? SessionKind.recovery
          : SessionKind.easy,
      meters: remainder * weights[i],
    );
  }
  return out;
}

/// Days between two weekdays, the short way round the week.
int _weekdayGap(int a, int b) {
  final raw = (a - b).abs();
  return raw > 3 ? 7 - raw : raw;
}

/// One non-long session's role in the week: what it is, and what share of the
/// week's remaining distance it takes.
typedef _Slot = ({SessionKind kind, double share});

/// How the week's non-long distance is split, in the order the days are filled.
///
/// **Not equally.** An earlier version divided the remainder by the number of
/// days, which handed a five-day runner four identical 6.5 km runs and a long
/// run. That is not a training week — it is a number divided by four. A week has
/// a shape: one quality session, a short day to recover from it, a medium-long
/// aerobic run mid-week, and something gentler before the long run.
///
/// The shares within each row sum to 1, and the row is ordered by *day*, not by
/// size. The largest easy run sits mid-week rather than the day before the long
/// run, and the shortest sits right after the quality session — which is where
/// the recovery is actually needed.
List<_Slot> _weekShape(int others, {required bool isDeload}) {
  const shapes = <int, List<_Slot>>{
    1: <_Slot>[(kind: SessionKind.easy, share: 1.00)],
    2: <_Slot>[
      (kind: SessionKind.threshold, share: 0.46),
      (kind: SessionKind.easy, share: 0.54),
    ],
    3: <_Slot>[
      (kind: SessionKind.threshold, share: 0.34),
      (kind: SessionKind.easy, share: 0.40),
      (kind: SessionKind.recovery, share: 0.26),
    ],
    4: <_Slot>[
      (kind: SessionKind.threshold, share: 0.26),
      (kind: SessionKind.recovery, share: 0.17),
      (kind: SessionKind.easy, share: 0.30),
      (kind: SessionKind.easy, share: 0.27),
    ],
    5: <_Slot>[
      (kind: SessionKind.threshold, share: 0.22),
      (kind: SessionKind.recovery, share: 0.14),
      (kind: SessionKind.easy, share: 0.24),
      (kind: SessionKind.easy, share: 0.22),
      (kind: SessionKind.easy, share: 0.18),
    ],
    6: <_Slot>[
      (kind: SessionKind.threshold, share: 0.19),
      (kind: SessionKind.recovery, share: 0.12),
      (kind: SessionKind.easy, share: 0.19),
      (kind: SessionKind.easy, share: 0.19),
      (kind: SessionKind.easy, share: 0.16),
      (kind: SessionKind.easy, share: 0.15),
    ],
  };

  if (others <= 0) return const <_Slot>[];
  final shape =
      shapes[others] ??
      <_Slot>[
        for (var k = 0; k < others; k++)
          (kind: SessionKind.easy, share: 1 / others),
      ];

  // A deload removes the stress, not the variety: the quality session becomes an
  // easy run of the same length rather than the week collapsing into seven
  // identical short ones.
  if (!isDeload) return shape;
  return <_Slot>[
    for (final s in shape)
      (kind: s.kind.isHard ? SessionKind.easy : s.kind, share: s.share),
  ];
}

/// Flattens [shape] toward an even split by exactly as much as it takes for
/// every session to stay under the long run.
///
/// The long run has to remain the week's longest session — the validator checks
/// it, and the plan arc shows its number. With only two non-long days the
/// remainder is about 65% of the week, so a shaped share can overtake a long run
/// that is only 35% of it, and the "long run" silently becomes an easy day.
///
/// Rather than tuning the table until it happens to fit, the shape is blended
/// toward equal shares by the smallest amount that satisfies the bound. Weeks
/// with room keep their shape untouched; only the ones that cannot have it give
/// it up, and they give up no more than they must.
List<_Slot> _fitUnderLongRun(
  List<_Slot> shape, {
  required double remainder,
  required double longRun,
}) {
  if (shape.length < 2 || remainder <= 0 || longRun <= 0) return shape;

  final equal = 1 / shape.length;
  final maxShare = shape.map((s) => s.share).reduce((a, b) => a > b ? a : b);
  if (maxShare * remainder <= longRun * _underLongRun) return shape;
  if (maxShare <= equal) return shape;

  final t = ((longRun * _underLongRun / remainder - equal) / (maxShare - equal))
      .clamp(0.0, 1.0);
  return <_Slot>[
    for (final s in shape) (kind: s.kind, share: t * s.share + (1 - t) * equal),
  ];
}

/// How close a non-long session may come to the long run. Strictly under, so
/// `longRunMeters` — which is just the week's maximum — keeps picking the
/// session that is actually the long run.
///
/// **Best effort, and deliberately not more.** Wider clearance was tried, to
/// stop two rows displaying the same rounded number. It cannot be delivered: a
/// blend toward an even split can never go *below* an even split without
/// breaking the week's total, and with three running days an even split is
/// already 32.5% of the week against a long run at 35%. Those two days really
/// are nearly as long as the long run — that is what a three-day week is — and
/// a plan should not be deformed to hide it. The rows say "Long run" and
/// "Easy", so a shared number reads fine.
///
/// Which means the *stored* numbers can tie too, now that both sit on the
/// whole-kilometre grid: 3% of a 5 km long run is 150 m and the grid step is a
/// thousand. Harmless, and worth being explicit about — the long run is the
/// session whose kind says so, never the biggest number in the week, and
/// nothing may start picking it that way.
const double _underLongRun = 0.97;

/// Days for strength work: available days the runner is *not* running, furthest
/// from the long run first, so a gym session never lands the day before it.
///
/// Doubles up on running days once the free ones run out — a runner who runs
/// five days on five available days has no empty day to give, and the answer is
/// to stack rather than to silently drop what they asked for. The earliest run
/// day goes first because it carries the quality session, and the standard
/// advice is to stack hard with hard and keep easy days easy.
///
/// The day before the long run is excluded throughout, free or not.
List<int> _strengthDays(List<int> available, List<int> runDays, int count) {
  if (count <= 0 || available.isEmpty) return const <int>[];
  final longDay = runDays.isEmpty ? 7 : runDays.last;
  final eve = longDay - 1;

  int furthestFromLong(int a, int b) =>
      (longDay - b).abs().compareTo((longDay - a).abs());

  final free = <int>[
    for (final d in available)
      if (!runDays.contains(d) && d != eve) d,
  ]..sort(furthestFromLong);

  // Run days to share, if it comes to that: the quality day first, then the
  // rest furthest from the long run. Never the long run's own day.
  final shared = <int>[
    for (final d in runDays.skip(1))
      if (d != longDay && d != eve) d,
  ]..sort(furthestFromLong);
  if (runDays.isNotEmpty && runDays.first != longDay && runDays.first != eve) {
    shared.insert(0, runDays.first);
  }

  return <int>[...free, ...shared].take(count).toList()..sort();
}

/// Picks [count] weekdays evenly spread across [sorted], keeping the latest day
/// (so the long run lands toward the weekend).
List<int> _spread(List<int> sorted, int count) {
  if (count >= sorted.length) return List<int>.of(sorted);
  if (count <= 1) return <int>[sorted.last];
  return <int>[
    for (var k = 0; k < count; k++)
      sorted[(k * (sorted.length - 1) / (count - 1)).round()],
  ];
}

/// The shortest block `buildSkeleton` will construct.
///
/// **Public, not `_minWeeks`, because `GoalDraft.issues` (EDGE-18) has to
/// refuse a race that would not leave this many weeks counted from the
/// coming Monday — the same number, not a second copy of it.** A block
/// shorter than this had nothing to build a block around, so `total` clamps
/// up to it regardless of how close the race actually is — which, before
/// that refusal existed, is exactly how a race 7–41 days out got a 6-week
/// skeleton with race day buried inside base or build and the taper left
/// scheduled for after it.
const int kMinPlanWeeks = 6;
const int _maxWeeks = 24;

/// How far ahead a horizon plan is drawn. Long enough to be a real arc, short
/// enough that it is not pretending to know a year of someone's life — it is
/// extended as they go, not planned to an end that does not exist.
const int _horizonWeeks = 12;

/// How far ahead a rhythm is drawn. It repeats, so this is only how much of it
/// is worth materialising at once.
const int _rhythmWeeks = 12;

/// Long run: ~35% of weekly volume, held under the absolute ceiling.
///
/// Kept exact. The runner is shown a round number, but the number the plan
/// worked out is what the plan keeps — it is what explains why they were shown
/// 7 km, and rounding it here would throw that away for a saving nobody asked
/// for. See `prescribed_distance.dart`.
///
/// Still true now that sessions are stored on the prescribed grid: the grid is
/// applied where a [PlannedSession] is built, not here. The skeleton keeps the
/// working — 35% of a week that came to 19,462 m — and the week prescribes
/// 19 km from it. Anything comparing the two has to allow for the difference;
/// [prescribedGridSlackMeters] is how much.
double _longRun(double volume) => math.min(volume * 0.35, 37000);

/// Phase per week (0-based). base ~40%, build ~40%, peak the rest, then taper.
List<Phase> _phases(int total, int taperWeeks) {
  final nonTaper = total - taperWeeks;
  var base = (nonTaper * 0.40).round();
  var peak = math.max(1, nonTaper - 2 * base);
  var build = nonTaper - base - peak;
  if (build < 1) {
    build = 1;
    base = math.max(1, nonTaper - build - peak);
    peak = nonTaper - base - build;
  }
  return <Phase>[
    for (var i = 0; i < total; i++)
      if (i >= nonTaper)
        Phase.taper
      else if (i < base)
        Phase.base
      else if (i < base + build)
        Phase.build
      else
        Phase.peak,
  ];
}

/// Deload weeks (0-based flags). A deload every ~4 weeks within the non-taper
/// block, with a tail guard so no run of >4 non-deload weeks reaches the event
/// (taper weeks count as non-deload in the invariant).
List<bool> _deloads(int total, int taperWeeks) {
  final deloads = List<bool>.filled(total, false);
  final nonTaper = total - taperWeeks;

  var sinceDeload = 0;
  for (var i = 1; i < nonTaper; i++) {
    sinceDeload++;
    if (sinceDeload >= 4) {
      deloads[i] = true;
      sinceDeload = 0;
    }
  }

  final lastDeload = deloads.lastIndexOf(true); // -1 if none
  if (total - 1 - lastDeload > 4) {
    final g = nonTaper - 1; // last non-taper week (0-based)
    if (g > lastDeload && g > 0) deloads[g] = true;
  }
  return deloads;
}
