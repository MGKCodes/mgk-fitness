import 'package:flutter/foundation.dart';

import '../features/coaching/data/coach_memory_repository.dart';
import '../features/coaching/data/coach_memory_store.dart';
import '../features/coaching/data/plan_repository.dart';
import '../features/coaching/data/plan_store.dart';
import '../features/coaching/domain/coach_memory.dart';
import '../features/coaching/domain/plan_shape.dart';
import '../features/coaching/domain/runner_profile.dart';
import '../features/coaching/domain/stored_plan.dart';
import '../features/recording/domain/run_summary.dart';
import 'dev_persona.dart';

/// Everything a [DevPersona] needs to stand up: the stores the shell reads and
/// the log behind them.
///
/// The stores are the **real in-memory implementations**, not fakes — the same
/// [InMemoryPlanStore] the preview harness and the widget tests use. A persona
/// therefore exercises the app's actual read path; only where the bytes come
/// from is different.
@immutable
class DevSeed {
  const DevSeed({
    required this.persona,
    required this.planStore,
    required this.memoryStore,
    required this.runs,
  });

  final DevPersona persona;

  /// Pre-loaded with this persona's plan, or empty for [DevPersona.fresh].
  final PlanStore planStore;

  /// Pre-loaded with what the coach remembers of them.
  final CoachMemoryStore memoryStore;

  /// The training log, newest first.
  final List<RunSummary> runs;

  /// Shaped as [HomeShell]'s `historySource`.
  Future<List<RunSummary>> history() async => runs;
}

/// Builds [persona]'s world.
///
/// Plans are created through the **real [PlanRepository]** with its clock wound
/// back, rather than by hand-assembling a [StoredPlan]. That matters: a
/// hand-built plan can be one the validator would have rejected, and then the
/// screens are being reviewed against a plan the app could never have produced.
/// Winding back `now` means a mid-block persona is a plan the app really did
/// build, three weeks ago.
///
/// [now] is injectable so tests are not at the mercy of the day they run on.
Future<DevSeed> buildDevSeed(DevPersona persona, {DateTime? now}) async {
  final today = now ?? DateTime.now();
  return switch (persona) {
    DevPersona.fresh => _fresh(persona),
    DevPersona.midBlock => _midBlock(persona, today),
    DevPersona.secondBlock => _secondBlock(persona, today),
    DevPersona.rhythm => _rhythm(persona, today),
    DevPersona.behind => _behind(persona, today),
  };
}

/// Mid-block, with the last few days empty and a run due today.
///
/// **Trains seven days a week on purpose.** Not because anyone should, but
/// because it is the only way to guarantee that whatever weekday the app is
/// opened on, today carries a prescribed run — so the Today card's primary
/// state is always reachable rather than reachable on the days the fixture
/// happens to allow.
///
/// The log stops four days back, which leaves this week's earlier sessions
/// missed and today's still to do (ADR-0017).
Future<DevSeed> _behind(DevPersona persona, DateTime today) async {
  final start = addDays(mondayOf(today), -21);
  final profile = RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: addDays(start, 16 * 7),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 7,
    availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  final store = await _planStartedOn(profile, start);
  final memory = await _remembering(
    summary:
        'Was consistent for three weeks and has gone quiet for the last few '
        'days. Has not said why.',
    said: const <(CoachRole, String)>[
      (CoachRole.user, 'Work has been a lot this week.'),
      (
        CoachRole.assistant,
        'Then we take what the week gives us. Tell me what you can get done '
            'and I will fit the rest around it.',
      ),
    ],
  );

  return DevSeed(
    persona: persona,
    planStore: store,
    memoryStore: memory,
    // Stops four days ago: the gap is the point of this persona.
    runs: _log(
      from: start,
      to: addDays(today, -4),
      perWeek: 5,
      weekly: 40000,
      pace: 312,
    ),
  );
}

/// Signed up, never run: no plan, no log, nothing remembered.
///
/// Deliberately built rather than special-cased away — "no persona" and "the
/// new-runner persona" must not be the same thing, or the empty states get
/// reviewed only by accident.
DevSeed _fresh(DevPersona persona) => DevSeed(
  persona: persona,
  planStore: InMemoryPlanStore(),
  memoryStore: InMemoryCoachMemoryStore(),
  runs: const <RunSummary>[],
);

/// Three weeks into a 16-week marathon build.
///
/// The plan starts on the Monday three weeks back, and the race is 16 weeks
/// after *that* — so today lands in week 4 with an arc either side of it.
Future<DevSeed> _midBlock(DevPersona persona, DateTime today) async {
  // Three whole weeks back from *this* week's Monday, so today lands in week 4
  // whichever weekday it happens to be.
  final start = addDays(mondayOf(today), -21);
  final profile = RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: addDays(start, 16 * 7),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    // Six free days for five runs, so the strength session has somewhere to go.
    availableWeekdays: const <int>{1, 2, 3, 4, 6, 7},
    strengthDaysPerWeek: 1,
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  final store = await _planStartedOn(profile, start);
  final memory = await _remembering(
    summary:
        'Building for a first marathon and more anxious about the distance '
        'than the time. Runs before work. A left calf that tightens on the '
        'faster sessions.',
    said: const <(CoachRole, String)>[
      (CoachRole.user, 'My left calf tightens on the faster stuff.'),
      (
        CoachRole.assistant,
        'Then we keep the threshold work honest rather than hard, and I would '
            'rather you cut a rep than push through it.',
      ),
    ],
  );

  return DevSeed(
    persona: persona,
    planStore: store,
    memoryStore: memory,
    // Three weeks of the block, actually run: five a week, building.
    runs: _log(from: start, to: today, perWeek: 5, weekly: 40000, pace: 312),
  );
}

/// A week-old block, standing on a season of running behind it.
///
/// [PlanStore] holds one plan (`loadActivePlan`), so "their second plan" cannot
/// be two plan rows — there is no plan history in the schema. It is expressed
/// the way it actually looks in the app: a new block whose log plainly predates
/// it by months. If plan history is ever wanted for its own sake, that is a
/// migration, not a fixture.
Future<DevSeed> _secondBlock(DevPersona persona, DateTime today) async {
  // Last Monday: the block is a week old, so it still reads as newly started.
  final start = addDays(mondayOf(today), -7);
  final profile = RunnerProfile(
    goalDistanceMeters: 21097.5,
    eventDate: addDays(start, 12 * 7),
    currentWeeklyMeters: 45000,
    longestRecentMeters: 21000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 3, 5, 6, 7},
    strengthDaysPerWeek: 1,
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 20, seconds: 30),
  );

  final store = await _planStartedOn(profile, start);
  final memory = await _remembering(
    summary:
        'Finished a first marathon in the spring and came back wanting to be '
        'quicker over the half rather than go longer. Knows the work; the '
        'question is always whether they are doing too much of it.',
    said: const <(CoachRole, String)>[
      (CoachRole.user, 'I finished the marathon. What now?'),
      (
        CoachRole.assistant,
        'Take the fortnight properly easy first. Then, if you want the half to '
            'be quick, we build around threshold rather than around distance — '
            'you already have the distance.',
      ),
    ],
  );

  // A season behind the new block: five months of running, then the block.
  final season = _log(
    from: addDays(start, -150),
    to: addDays(start, -1),
    perWeek: 4,
    weekly: 38000,
    pace: 322,
  );
  final current = _log(
    from: start,
    to: today,
    perWeek: 5,
    weekly: 45000,
    pace: 305,
  );

  return DevSeed(
    persona: persona,
    planStore: store,
    memoryStore: memory,
    runs: <RunSummary>[...current, ...season],
  );
}

/// One run a week, every week, going nowhere in particular.
///
/// No goal and no date, so [shapeOf] reads this as a [PlanShape.rhythm]: no
/// ramp, no taper, and a plan that never ends. The single Saturday commitment
/// *is* the week.
Future<DevSeed> _rhythm(DevPersona persona, DateTime today) async {
  // Twenty weeks of Saturdays behind them. A rhythm's weeks cycle, so the
  // start date is about how long they have kept it up, not how far in they are.
  final start = addDays(mondayOf(today), -140);
  const profile = RunnerProfile(
    currentWeeklyMeters: 5000,
    longestRecentMeters: 5000,
    daysPerWeek: 1,
    availableWeekdays: <int>{DateTime.saturday},
    commitments: <PlanCommitment>[
      PlanCommitment(
        weekday: DateTime.saturday,
        distanceMeters: 5000,
        label: 'parkrun',
        timed: true,
      ),
    ],
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: Duration(minutes: 26, seconds: 40),
  );

  final store = await _planStartedOn(profile, start);
  final memory = await _remembering(
    summary:
        'Runs parkrun on Saturdays and has no interest in a race. Turning up '
        'every week is the point; getting quicker is a bonus they will take '
        'but will not train for.',
    said: const <(CoachRole, String)>[
      (CoachRole.user, 'I do not want a training plan, I just do parkrun.'),
      (
        CoachRole.assistant,
        'Then that is the plan. Saturdays, and I will tell you what the last '
            'few weeks say about your form rather than what you should be '
            'building toward.',
      ),
    ],
  );

  // Twenty Saturdays, drifting slightly quicker — enough for the consistency
  // count to have something real to count.
  final saturdays = <RunSummary>[];
  for (var i = 0; i < 20; i++) {
    final at = addDays(today, -7 * i);
    final saturday = addDays(at, DateTime.saturday - at.weekday);
    if (saturday.isAfter(today)) continue;
    final seconds = 1620 - i * 5;
    saturdays.add(
      RunSummary(
        startedAt: DateTime(saturday.year, saturday.month, saturday.day, 9),
        duration: Duration(seconds: seconds),
        distanceMeters: 5000,
        avgPaceSecondsPerKm: seconds / 5,
        elevationGainMeters: 24,
        avgHr: 158,
      ),
    );
  }

  return DevSeed(
    persona: persona,
    planStore: store,
    memoryStore: memory,
    runs: saturdays,
  );
}

/// Creates [profile]'s plan **as of [start]** and returns the store holding it.
///
/// The clock is wound back for the whole call, so `startDate` is [start] and the
/// skeleton is the length the arc had when it was built. The validator still
/// runs: a fixture the app would have refused to store throws here rather than
/// quietly becoming something to design against.
Future<PlanStore> _planStartedOn(RunnerProfile profile, DateTime start) async {
  final store = InMemoryPlanStore();
  // No backup: a persona must never reach Supabase. Seeded runs pushed to the
  // shared project would be indistinguishable from the runner's own.
  await PlanRepository(store: store, now: () => start).create(profile);
  return store;
}

/// A memory store already holding a rolling summary and the turns behind it.
Future<CoachMemoryStore> _remembering({
  required String summary,
  required List<(CoachRole, String)> said,
}) async {
  final store = InMemoryCoachMemoryStore();
  // Through the repository rather than the store, so a persona's memory is
  // built by the same path the coach writes it by.
  final memory = CoachMemoryRepository(store: store);
  for (final (role, text) in said) {
    await memory.appendTurn(
      conversationId: 'dev-persona',
      role: role,
      text: text,
    );
  }
  await memory.replaceSummary(summary, turnsCovered: said.length);
  return store;
}

/// A plausible training log between two dates, newest first.
///
/// [weekly] is split across [perWeek] runs with one of them long, so the totals
/// on Profile are the ones the plan's volume implies rather than numbers that
/// merely look busy.
List<RunSummary> _log({
  required DateTime from,
  required DateTime to,
  required int perWeek,
  required double weekly,
  required double pace,
}) {
  final runs = <RunSummary>[];
  // The long run is ~30% of the week; the rest share what is left evenly.
  final long = weekly * 0.30;
  final easy = (weekly - long) / (perWeek - 1);
  // The shorter runs run from Monday; the long one is Sunday (offset 6).
  final days = <int>[for (var i = 0; i < perWeek - 1; i++) i];

  var week = mondayOf(from);
  var index = 0;
  while (!week.isAfter(to)) {
    for (final d in days) {
      final at = addDays(week, d);
      if (at.isBefore(from) || at.isAfter(to)) continue;
      // A little variation so the log does not read as a spreadsheet.
      final meters = easy * (1 + ((index % 3) - 1) * 0.12);
      final secondsPerKm = pace + ((index % 4) - 1) * 6;
      runs.add(_paced(at: at, meters: meters, secondsPerKm: secondsPerKm));
      index++;
    }
    final longDay = addDays(week, 6);
    if (!longDay.isBefore(from) && !longDay.isAfter(to)) {
      runs.add(
        _paced(at: longDay, meters: long, secondsPerKm: pace + 28, long: true),
      );
    }
    week = addDays(week, 7);
  }
  runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return runs;
}

/// A run whose duration actually matches its pace.
///
/// The arithmetic is enforced here rather than trusted at each call site: the
/// standing card reads pace back out of duration over distance, so a fixture
/// that sets the two independently makes correct code look broken.
RunSummary _paced({
  required DateTime at,
  required double meters,
  required double secondsPerKm,
  bool long = false,
}) {
  final rounded = (meters / 100).round() * 100.0;
  return RunSummary(
    startedAt: DateTime(at.year, at.month, at.day, long ? 9 : 7, 10),
    duration: Duration(seconds: (rounded / 1000 * secondsPerKm).round()),
    distanceMeters: rounded,
    avgPaceSecondsPerKm: secondsPerKm,
    elevationGainMeters: long ? 96 : 38,
    avgHr: long ? 148 : 143,
  );
}
