import 'plan.dart';
import 'plan_validator.dart';

/// Where a plan lives between sessions.
///
/// Deliberately small. A plan is written once when it is generated, flipped to
/// active once when it is accepted, and touched thereafter only as sessions are
/// trained or a movement is swapped. Anything richer would be inventing
/// operations nothing performs.
abstract interface class PlanStore {
  /// The lifter's live block, or null. Throws [PlanException].
  Future<Plan?> active();

  /// Writes a plan and everything under it.
  Future<void> save(Plan plan);

  /// Makes a draft the live block, standing down any incumbent first.
  Future<Plan> accept(Plan draft);

  /// Records that a planned session was actually trained, and as which workout.
  Future<void> markTrained(PlanSession session, String workoutId);

  /// Replaces a planned session's movements — what a mid-session swap leaves
  /// behind, so the plan does not go on claiming they did something they
  /// changed.
  Future<void> replaceMovements(
    PlanSession session,
    List<PlannedMovement> movements,
  );
}

/// A plan store with nothing behind it, for tests and the preview harness.
class InMemoryPlanStore implements PlanStore {
  InMemoryPlanStore([this._plan]);

  Plan? _plan;

  /// What was written, in order, so a test can assert the sequence rather than
  /// only the end state.
  final List<String> calls = <String>[];

  @override
  Future<Plan?> active() async =>
      _plan?.status == PlanStatus.active ? _plan : null;

  @override
  Future<void> save(Plan plan) async {
    calls.add('save:${plan.id}');
    _plan = plan;
  }

  @override
  Future<Plan> accept(Plan draft) async {
    calls.add('accept:${draft.id}');
    return _plan = draft.copyWith(status: PlanStatus.active);
  }

  @override
  Future<void> markTrained(PlanSession session, String workoutId) async {
    calls.add('trained:${session.id}:$workoutId');
    final plan = _plan;
    if (plan == null) return;
    _plan = plan.copyWith(
      sessions: <PlanSession>[
        for (final s in plan.sessions)
          if (s.id == session.id)
            s.copyWith(
              status: PlanSessionStatus.completed,
              workoutId: workoutId,
            )
          else
            s,
      ],
    );
  }

  @override
  Future<void> replaceMovements(
    PlanSession session,
    List<PlannedMovement> movements,
  ) async {
    calls.add('movements:${session.id}');
    final plan = _plan;
    if (plan == null) return;
    _plan = plan.copyWith(
      sessions: <PlanSession>[
        for (final s in plan.sessions)
          if (s.id == session.id) s.copyWith(movements: movements) else s,
      ],
    );
  }
}
