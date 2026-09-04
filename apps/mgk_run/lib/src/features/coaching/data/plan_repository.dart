import 'package:mgk_units/mgk_units.dart';

import '../../recording/domain/run_summary.dart';
import '../domain/plan_builder.dart';
import '../domain/plan_headline.dart';
import '../domain/plan_history.dart';
import '../domain/plan_shape.dart';
import '../domain/plan_validator.dart';
import '../domain/race_day.dart';
import '../domain/runner_profile.dart';
import '../domain/session_status.dart';
import '../domain/stored_plan.dart';
import '../domain/training_plan.dart';
import 'plan_service.dart';
import 'plan_store.dart';

/// The plan's persistence logic, sitting on a [PlanStore].
///
/// **Offline-first (CLAUDE.md rule 1):** every read and every write goes to the
/// local store first and completes there. [PlanBackup] is then poked
/// best-effort; a failed or absent backup can never fail a write or block a
/// read, so the runner's plan does not depend on the network.
///
/// **The validator disposes (rule 2):** a skeleton is validated *before* it is
/// persisted. Nothing the validator would reject is allowed onto disk, so a plan
/// reloaded next launch is exactly as sound as the day it was generated.
class PlanRepository {
  PlanRepository({
    required PlanStore store,
    PlanBackup? backup,
    PlanService? generator,
    DateTime Function() now = DateTime.now,
    this.rules,
    String Function()? newId,
  }) : _store = store,
       _backup = backup,
       _generator = generator,
       _now = now,
       _newId = newId ?? _defaultId;

  final PlanStore _store;
  final PlanBackup? _backup;

  /// The model-backed generator, or null for a plan built entirely in Dart.
  ///
  /// Null is a real configuration, not a degraded one: a dev persona, a build
  /// with no backend, and every widget test run without it. What it is *not* is
  /// the shipping default — for a year this field did not exist and nothing
  /// constructed [PlanService] outside its own tests, so every plan Runio made
  /// was the deterministic fallback. The arc the runner was shown as their
  /// coach's work was `buildSkeleton`.
  final PlanService? _generator;
  final DateTime Function() _now;
  final String Function() _newId;

  /// Overrides the per-shape rule set. Null — the default — means each plan is
  /// judged by the rules for its own shape (ADR-0011).
  final PlanRules? rules;

  /// Every plan the runner has had, oldest first and labelled.
  ///
  /// Local only, like every other read here. Returns empty rather than throwing
  /// on a store that cannot answer: history is context, and a screen that hid
  /// the current plan because an old one was unreadable would lose the useful
  /// thing to protect the ornamental one.
  Future<List<LabelledPlan>> history() async {
    try {
      return labelPlans(await _store.loadHistory());
    } on PlanStoreException {
      return const <LabelledPlan>[];
    }
  }

  /// The runner's stored plan, or null if they have none.
  ///
  /// Local only — no network involved, so this resolves in a tunnel. Propagates
  /// [PlanStoreException] if a plan exists but is unreadable; the caller must
  /// show that as a problem, not as an empty state.
  Future<StoredPlan?> load() => _store.loadActivePlan();

  /// Builds a plan for [profile] and persists it, superseding any existing plan.
  ///
  /// The skeleton is validated first: an invalid arc is a bug in generation, and
  /// storing it would bake that bug into the runner's block. Throws
  /// [PlanStoreException] listing the violations rather than persisting it.
  ///
  /// The current week's sessions are generated and stored in the same call, so
  /// today's session — and any mark on it — is durable from the moment the plan
  /// exists rather than from the next time the tab happens to build.
  Future<StoredPlan> create(RunnerProfile profile) async {
    final now = _now();
    // The one place a wait is honest: the runner has just tapped "Build my
    // plan" and is watching a spinner that says so. Every other path into this
    // file is a screen already on screen, which is why they stay local.
    final generator = _generator;
    final skeleton = generator == null
        ? buildSkeleton(profile, now: now)
        : (await generator.generateSkeleton(profile)).plan;

    // Judged by its own shape's rules. A repository holding one rule set
    // rejects every plan that is not a block — which is how a parkrun runner's
    // plan failed to be created at all.
    final result = validateSkeleton(
      skeleton,
      profile,
      rules: rules ?? PlanRules.forShape(shapeOf(profile)),
    );
    if (!result.isValid) {
      throw PlanStoreException(
        'refusing to store a skeleton the validator rejects: '
        '${result.violations.join('; ')}',
      );
    }

    final plan = StoredPlan(
      id: _newId(),
      profile: profile,
      skeleton: skeleton,
      startDate: mondayOf(now),
    );
    await _store.savePlan(plan);
    await _pushPlan(plan);

    // Materialise this week and the next, under the same spinner. One week
    // ahead is what plan-generation.md specifies, and doing it here rather than
    // lazily is what keeps [weekFor] off the network: by the time any screen
    // asks, the horizon the Coach tab shows is already on disk.
    final current = plan.weekOn(now);
    await weekFor(plan, current, allowModel: true);
    final next = plan.skeleton.weeks.firstWhere(
      (w) => w.index == current.index + 1,
      orElse: () => current,
    );
    if (next.index != current.index) {
      await weekFor(plan, next, allowModel: true);
    }
    return plan;
  }

  /// The sessions for [slot], generating and storing them the first time the
  /// week is asked for.
  ///
  /// **[allowModel] defaults to false, and that default is the offline-first
  /// rule doing its job.** Every caller but [create] and [lookAhead] is a screen
  /// already drawn — the Today card, the week ribbon, the calendar — and a
  /// model call there means the Coach tab hangs on a spinner for as long as the
  /// network takes to fail. [PlanService] does fall back deterministically, but
  /// only after two attempts have timed out, so the runner in a tunnel waits
  /// twice for the answer Dart could have given at once. The plan is owned by
  /// the device (CLAUDE.md rule 1); reading it must never need the network.
  ///
  /// Weeks are stored as generated rather than re-validated on the way in: the
  /// deterministic builder satisfies [validateWeek] by construction, and the
  /// model path is already gated by [PlanService].
  Future<TrainingWeek> weekFor(
    StoredPlan plan,
    SkeletonWeek slot, {
    bool allowModel = false,
  }) async {
    final stored = await _store.loadWeek(plan, slot.index);
    if (stored != null) return stored;

    final generator = _generator;
    final unusable = _unusableWeekdays(plan, slot);
    final week = (allowModel && generator != null)
        ? (await generator.generateWeek(
            slot,
            plan.profile,
            // At most one day, and only in the week that holds the race.
            raceWeekday: unusable.isEmpty ? null : unusable.first,
          )).plan
        : buildFallbackWeek(slot, plan.profile, unusableWeekdays: unusable);
    await _store.saveWeek(plan, week);
    await _pushWeek(plan, week);
    return week;
  }

  /// Days this week has that cannot carry a session, whatever the runner said.
  ///
  /// **The only place in the plan stack where weekdays meet dates.**
  ///
  /// Race day, and for now only race day. It is the event (ADR-0027), the whole
  /// block is built to arrive at it, and the deterministic builder puts the
  /// long run on the latest available weekday -- which in the final week is
  /// usually the Sunday the race is on. Found on a phone, as row D4.
  ///
  /// **The sibling defect is not fixed here, deliberately.** A plan built on a
  /// Friday also opens with Monday to Thursday behind it, because the grid is
  /// anchored to `mondayOf(now)`. Excluding those days the same way was tried
  /// and reverted: it leaves week 1 with three usable days carrying a whole
  /// week's prescribed volume, which trades a week nobody can complete for a
  /// week nobody should. The real fix is the anchor -- start on the coming
  /// Monday, or count the block backwards from race day as ADR-0027 already
  /// says it does -- and that changes what every plan looks like, so it is a
  /// decision rather than a patch. `now` is kept here for it.
  Set<int> _unusableWeekdays(StoredPlan plan, SkeletonWeek slot) {
    final DateTime? event = plan.profile.eventDate;
    final DateTime? race = event == null
        ? null
        : DateTime(event.year, event.month, event.day);

    final out = <int>{};
    for (var weekday = 1; weekday <= 7; weekday++) {
      final DateTime on = plan.dateFor(weekIndex: slot.index, weekday: weekday);
      final DateTime day = DateTime(on.year, on.month, on.day);
      if (race != null && day.isAtSameMomentAs(race)) out.add(weekday);
    }
    return out;
  }

  /// Fills the coming week's sessions from the model, if they are not there yet.
  ///
  /// Called after a screen has painted, never before it. The distinction from
  /// [weekFor] is who is waiting: nobody is waiting on this, so it can afford
  /// the network.
  ///
  /// **Only a week the model actually produced is written.** If it was
  /// unreachable, [PlanService] hands back a deterministic week and this drops
  /// it on the floor — because storing it would settle the question. A week on
  /// disk is never regenerated, so a fallback written here while the runner was
  /// on a train would be the week they trained, permanently, with nothing to
  /// say it had ever been second choice. Left unwritten, the screen that needs
  /// it still builds one in Dart and the next look-ahead tries the model again.
  ///
  /// Returns true if it wrote a week. Never throws — a look-ahead that surfaced
  /// an error would be reporting a failure at something the runner did not ask
  /// for and cannot see.
  Future<bool> lookAhead(StoredPlan plan) async {
    final generator = _generator;
    if (generator == null) return false;
    final now = _now();
    final current = plan.weekOn(now);
    final next = plan.skeleton.weeks.where((w) => w.index == current.index + 1);
    if (next.isEmpty) return false;

    final slot = next.first;
    try {
      if (await _store.loadWeek(plan, slot.index) != null) return false;
      final result = await generator.generateWeek(slot, plan.profile);
      if (result.isFallback) return false;
      await _store.saveWeek(plan, result.plan);
      await _pushWeek(plan, result.plan);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Persists a week the runner revised through the adaptation flow.
  ///
  /// Mirrors [weekFor]'s storage path for the same reason it does not
  /// re-validate: [AdaptationService] already runs `validateWeek` against the
  /// slot and refuses a revision that fails, so anything arriving here has been
  /// disposed of by the validator. Statuses already recorded against the week
  /// survive — the store updates sessions in place rather than replacing them.
  Future<void> saveRevisedWeek(StoredPlan plan, TrainingWeek week) async {
    await _store.saveWeek(plan, week);
    await _pushWeek(plan, week);
  }

  /// Everything the Today card needs, resolved against **one** reading of the
  /// clock — so the phase, the session and its status can never disagree about
  /// which day it is (a real hazard at midnight, or across a slow load).
  ///
  /// Materialises the current week first, so a null session unambiguously means
  /// "rest day" rather than "not generated yet".
  Future<TodayView> today(
    StoredPlan plan, {
    UnitSystem unit = UnitSystem.metric,
  }) async {
    final now = _now();
    final slot = plan.weekOn(now);
    final week = await weekFor(plan, slot);
    final session = week.runOn(now.weekday);
    // A strength day is not a rest day. [runs] filters to running, so a day
    // carrying only support work came back null and Home called it "Rest day ·
    // Nothing scheduled" while the Plan tab, reading the same week, listed
    // Strength on it. Runio does not prescribe what is *in* a strength session
    // (ADR-0010) — it still has to admit the day is spoken for.
    final support = session == null ? week.sessionOn(now.weekday) : null;
    return TodayView(
      slot: slot,
      session: session,
      support: support,
      heading: todayHeading(plan.profile, slot),
      // Resolved here for the reason [heading] is: whether today is race day,
      // three days out, or the morning after is a property of the plan's
      // shape, and the card takes the answer and asks nothing (ADR-0011).
      // Null for a horizon, a rhythm and a log — none of which has a date to
      // arrive at — and for the ordinary run of a block, which is most days.
      race: raceOutlookFor(plan, now, unit: unit),
      status: session == null
          ? SessionStatus.planned
          : await _store.statusOn(plan, now) ?? SessionStatus.planned,
    );
  }

  /// Closes [plan] out — it reached its own end rather than being replaced.
  ///
  /// **The one write in this file the runner is watching.** Everything else
  /// here is a screen loading; this is the moment sixteen weeks stop being the
  /// plan, so it completes on disk before anything is shown (the same contract
  /// [markToday] has, for the same reason).
  ///
  /// [raceTime] is what they confirmed they ran, and is dropped for a runner
  /// who did not race — see [PlanStore.closePlan].
  ///
  /// **Not mirrored.** `finished_at` and `race_time_s` are schema 10 columns
  /// with no counterpart in the `run` Postgres schema, so [PlanBackup] does not
  /// carry them and there is nothing to push. That is the position `runs.steps`
  /// and `elevation_max_m` are in (ADR-0024) and for the same reason: the
  /// schema lives in `supabase/` at the repo root and is not this app's to
  /// change. The cost is stated at the seam in `plan_backup_rows.dart`.
  Future<void> finish(
    StoredPlan plan, {
    required PlanClosure closure,
    Duration? raceTime,
  }) => _store.closePlan(plan, closure: closure, raceTime: raceTime);

  /// Closes a plan whose race is long past and which the runner never closed,
  /// and answers how — or null when it is still theirs to close.
  ///
  /// **This is the runner who never races.** It is common: they get injured in
  /// week eleven, or the entry never happened, or the event was cancelled, and
  /// the thing they do next is stop opening the app. Nothing about that
  /// produces a tap, so nothing would ever end the plan — the coach would keep
  /// briefing against a marathon that happened last spring, and Profile would
  /// never list it among the things they have trained for.
  ///
  /// Called from the refresh that loads the plan rather than from [load],
  /// deliberately: a read that writes is a read nobody can reason about, and
  /// there are half a dozen callers of [load] that have no business closing
  /// anything.
  ///
  /// A store that refuses the close answers null rather than raising: the plan
  /// is then exactly as it was, which is the state this exists to tidy and not
  /// one that can hurt anybody in the meantime. Nobody asked for this and
  /// nobody can see it, so there is nothing to report.
  Future<PlanClosure?> closeIfOverdue(
    StoredPlan plan,
    List<RunSummary> runs,
  ) async {
    final closure = overdueClosureFor(plan, runs, _now());
    if (closure == null) return null;
    // Read from the log, which is the same evidence the runner would have been
    // shown before confirming. Null for the didNotRace case by construction —
    // [overdueClosureFor] only answers `raced` when there is a run to read.
    final result = raceResultFor(plan, runs);
    try {
      await finish(plan, closure: closure, raceTime: result?.time);
    } on PlanStoreException {
      return null;
    }
    return closure;
  }

  /// Marks today's session done / skipped / planned again.
  ///
  /// The returned future completes only once the mark is **on disk**, so a
  /// force-quit straight after tapping keeps it. Returns false if there was no
  /// session today to mark.
  Future<bool> markToday(StoredPlan plan, SessionStatus status) async {
    final now = _now();
    final marked = await _store.setStatusOn(plan, now, status);
    if (!marked) return false;
    await _pushStatus(plan, now, status);
    return true;
  }

  // --- backup: best effort, never load-bearing --------------------------------

  Future<void> _pushPlan(StoredPlan plan) =>
      _bestEffort(() => _backup?.pushPlan(plan));

  Future<void> _pushWeek(StoredPlan plan, TrainingWeek week) =>
      _bestEffort(() => _backup?.pushWeek(plan, week));

  Future<void> _pushStatus(
    StoredPlan plan,
    DateTime date,
    SessionStatus status,
  ) => _bestEffort(
    () => _backup?.pushStatus(
      plan: plan,
      weekIndex: plan.weekIndexOn(date),
      weekday: date.weekday,
      date: date,
      status: status,
    ),
  );

  /// Runs a backup push, swallowing anything it throws. The local write has
  /// already committed, so a dead network is not an error the runner needs to
  /// see. Deliberately silent: a plan is derived from health data, and CLAUDE.md
  /// rule 6 forbids logging those values.
  Future<void> _bestEffort(Future<void>? Function() push) async {
    try {
      await push();
    } catch (_) {
      // Ignored on purpose — see above.
    }
  }
}

String _defaultId() => 'plan-${DateTime.now().microsecondsSinceEpoch}';

/// The Today card's state, read as one consistent snapshot by
/// [PlanRepository.today].
class TodayView {
  const TodayView({
    required this.slot,
    required this.session,
    required this.status,
    required this.heading,
    this.support,
    this.race,
  });

  /// The skeleton week today falls in.
  final SkeletonWeek slot;

  /// What to head the card — already resolved for the plan's shape, so the
  /// card can draw it without knowing there are shapes ([todayHeading]).
  final String heading;

  /// Today's run, or null when nothing is prescribed to *run* today.
  final PlannedSession? session;

  /// Today's support work — strength — when there is no run. Null both on a
  /// genuine rest day and on a day that already has a run, so a non-null value
  /// means "no run, but the day is still spoken for".
  final PlannedSession? support;

  /// The race, when it is close enough to matter — already resolved for the
  /// plan's shape, so the card draws it without knowing there are shapes.
  ///
  /// Null on the overwhelming majority of days, and null for every plan that
  /// is not aimed at a date. A card reading this must not treat null as an
  /// error state: it means "an ordinary day", which is what most days are.
  final RaceOutlook? race;

  /// Only meaningful when [session] is non-null.
  final SessionStatus status;
}
