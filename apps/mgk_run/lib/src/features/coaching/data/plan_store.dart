import '../domain/plan_history.dart';
import '../domain/session_status.dart';
import '../domain/stored_plan.dart';
import '../domain/training_plan.dart';

/// Local persistence for a training plan — **the source of truth** (CLAUDE.md
/// rule 1). Every method here must work with no network; Supabase is a backup
/// reached separately via [PlanBackup].
///
/// Implementations: [DriftPlanStore] on device, [InMemoryPlanStore] for the
/// preview harness and tests.
abstract interface class PlanStore {
  /// The runner's current plan, or null if they have none.
  ///
  /// Throws [PlanStoreException] if a stored plan exists but cannot be decoded —
  /// never returns null in that case, because "no plan yet" and "your plan is
  /// unreadable" must not look the same to the runner.
  Future<StoredPlan?> loadActivePlan();

  /// Stores [plan], superseding any plan already active. Atomic: a failure
  /// leaves the previous plan intact rather than half-replacing it.
  Future<void> savePlan(StoredPlan plan);

  /// Every plan the runner has had, **oldest first**, including the current one.
  ///
  /// Oldest first because the labels are numbered from the first plan and have
  /// to stay put — see [labelPlans]. Light by design: no skeleton is loaded, so
  /// this stays cheap enough to read on the way into a screen.
  ///
  /// Each record's `endedAt` is the creation date of whatever replaced it, which
  /// is why this returns the whole list rather than offering a single-plan read:
  /// a plan's end is a fact about the plan *after* it.
  Future<List<PlanRecord>> loadHistory();

  /// The stored sessions of week [weekNumber], or null if that week has not been
  /// generated yet — sessions come a week ahead (plan-generation.md).
  Future<TrainingWeek?> loadWeek(StoredPlan plan, int weekNumber);

  /// Stores [week]'s sessions, replacing whatever was there. Statuses the runner
  /// already set survive the rewrite.
  Future<void> saveWeek(StoredPlan plan, TrainingWeek week);

  /// The status of the session on [date], or null for a rest day / a day with no
  /// stored session.
  Future<SessionStatus?> statusOn(StoredPlan plan, DateTime date);

  /// Marks the session on [date]. Returns false when there was no session to
  /// mark, so a caller cannot mistake a no-op for a durable write.
  ///
  /// The returned future completes only once the mark is on disk.
  Future<bool> setStatusOn(
    StoredPlan plan,
    DateTime date,
    SessionStatus status,
  );
}

/// The backup / cross-device half: a best-effort mirror of what is already
/// safely on disk. Never on the read path, and never allowed to fail a write —
/// the runner's plan does not depend on the network.
abstract interface class PlanBackup {
  Future<void> pushPlan(StoredPlan plan);
  Future<void> pushWeek(StoredPlan plan, TrainingWeek week);
  Future<void> pushStatus({
    required StoredPlan plan,
    required int weekIndex,
    required int weekday,
    required DateTime date,
    required SessionStatus status,
  });
}

/// A stored plan could not be read or written. Raised rather than swallowed:
/// silently returning "no plan" would lose the runner's block behind an empty
/// state that invites them to build another one.
class PlanStoreException implements Exception {
  const PlanStoreException(this.message);

  final String message;

  @override
  String toString() => 'PlanStoreException: $message';
}

/// An in-memory [PlanStore]. The default when nothing is injected, so the plan
/// tab has exactly one code path whether or not a database is wired up, and the
/// preview harness exercises the real read/write flow with no Supabase and no
/// device plugins.
///
/// Not durable across launches — that is [DriftPlanStore]'s job.
class InMemoryPlanStore implements PlanStore {
  InMemoryPlanStore({DateTime Function() now = DateTime.now}) : _now = now;

  StoredPlan? _plan;
  final Map<int, TrainingWeek> _weeks = <int, TrainingWeek>{};
  final Map<String, SessionStatus> _statuses = <String, SessionStatus>{};

  /// Superseded plans, oldest first, with the moment each stopped being active.
  /// Kept because history is a feature rather than a database detail — a store
  /// that forgot them would make the preview and every widget test look like a
  /// runner who has never had a plan.
  final List<(StoredPlan, DateTime)> _past = <(StoredPlan, DateTime)>[];
  final DateTime Function() _now;

  @override
  Future<StoredPlan?> loadActivePlan() async => _plan;

  @override
  Future<void> savePlan(StoredPlan plan) async {
    // A new plan supersedes the old one: its weeks and marks do not carry over.
    final previous = _plan;
    if (previous != null && previous.id != plan.id) {
      _past.add((previous, _now()));
    }
    _plan = plan;
    _weeks.clear();
    _statuses.clear();
  }

  @override
  Future<List<PlanRecord>> loadHistory() async => <PlanRecord>[
    for (final (plan, endedAt) in _past) _recordOf(plan, endedAt: endedAt),
    if (_plan != null) _recordOf(_plan!, active: true),
  ];

  static PlanRecord _recordOf(
    StoredPlan plan, {
    DateTime? endedAt,
    bool active = false,
  }) => PlanRecord(
    id: plan.id,
    startDate: plan.startDate,
    weeks: plan.skeleton.weeks.length,
    isActive: active,
    goalDistanceMeters: plan.profile.goalDistanceMeters,
    eventDate: plan.profile.eventDate,
    endedAt: endedAt,
  );

  @override
  Future<TrainingWeek?> loadWeek(StoredPlan plan, int weekNumber) async =>
      _plan?.id == plan.id ? _weeks[weekNumber] : null;

  @override
  Future<void> saveWeek(StoredPlan plan, TrainingWeek week) async {
    _weeks[week.skeletonIndex] = week;
  }

  @override
  Future<SessionStatus?> statusOn(StoredPlan plan, DateTime date) async {
    if (_sessionOn(plan, date) == null) return null;
    return _statuses[_key(date)] ?? SessionStatus.planned;
  }

  @override
  Future<bool> setStatusOn(
    StoredPlan plan,
    DateTime date,
    SessionStatus status,
  ) async {
    if (_sessionOn(plan, date) == null) return false;
    _statuses[_key(date)] = status;
    return true;
  }

  PlannedSession? _sessionOn(StoredPlan plan, DateTime date) {
    final week = _weeks[plan.weekIndexOn(date)];
    return week?.runOn(date.weekday);
  }

  static String _key(DateTime date) => '${date.year}-${date.month}-${date.day}';
}
