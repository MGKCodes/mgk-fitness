import 'package:meta/meta.dart';

import 'coach_planner.dart';
import 'plan_intake.dart';
import 'standing_plan.dart';

/// Where a standing plan is kept.
///
/// ## Smaller than the block store it replaces, and that is the point
///
/// The block store had five methods, three of which existed because the plan
/// was a list of sessions written in advance: `markTrained` stamped a session
/// row when its workout finished, `replaceMovements` rewrote one after a swap,
/// and `accept` promoted a whole generated block from draft to active.
///
/// A standing plan has no session rows to stamp. A finished workout updates the
/// SLOT it came from — the top set and how long it has been stuck — which is
/// one write against a couple of dozen rows that outlive every session, rather
/// than a rewrite of a schedule. So the store is: read the live one, replace
/// it, and record what a session did to a slot.
abstract interface class StandingPlanStore {
  /// The live plan, or null if there is not one.
  Future<StandingPlan?> active();

  /// Replaces whatever is live.
  ///
  /// **One live plan per person**, enforced by a partial unique index in the
  /// database rather than here — two active plans is not a state with a
  /// meaning, because the plan screen would have to choose which one today
  /// belongs to and would be wrong half the time.
  ///
  /// The plan being replaced becomes `superseded` rather than disappearing:
  /// "I do not like this split" should not erase what somebody has run.
  ///
  /// [intake] is what the lifter told the coach to get this plan — goal, kit,
  /// what they are working around. Kept with the plan, because it was asked
  /// once and is what the coach should still know the next time it is talked
  /// to. Before 2026-10-07 nothing kept it: the columns existed and every
  /// answer was dropped the moment the plan was built.
  ///
  /// **All or nothing.** A plan with no slots is not a smaller plan; it is a
  /// Plan tab with a name and no sessions. Either the new plan is live with
  /// every slot, or the old one still is.
  Future<StandingPlan> replace(StandingPlan plan, {PlanIntake? intake});

  /// What a finished session did to one slot.
  ///
  /// Called once per movement when a workout is finished. [topKg] and [reps]
  /// are the best set; passing a lighter one than last time deliberately does
  /// NOT count as movement, because a lighter session is a lighter session
  /// rather than a regression to program around.
  Future<void> recordResult(
    String slotId, {
    required double topKg,
    required int reps,
    required bool improved,
  });
}

/// A store that keeps everything in memory, for tests and the preview harness.
@visibleForTesting
class InMemoryStandingPlanStore implements StandingPlanStore {
  InMemoryStandingPlanStore([this._plan]);

  StandingPlan? _plan;

  /// Everything asked of it, in order, so a test can assert what was written.
  final List<String> calls = <String>[];

  @override
  Future<StandingPlan?> active() async => _plan;

  /// What the last [replace] was told, so a test can assert it was kept.
  PlanIntake? intake;

  @override
  Future<StandingPlan> replace(StandingPlan plan, {PlanIntake? intake}) async {
    calls.add('replace:${plan.id}');
    this.intake = intake;
    return _plan = plan;
  }

  @override
  Future<void> recordResult(
    String slotId, {
    required double topKg,
    required int reps,
    required bool improved,
  }) async {
    calls.add('result:$slotId:$topKg×$reps:${improved ? 'up' : 'held'}');
    final plan = _plan;
    if (plan == null) return;
    _plan = StandingPlan(
      id: plan.id,
      name: plan.name,
      dayOrder: plan.dayOrder,
      weekdays: plan.weekdays,
      rationale: plan.rationale,
      startedAt: plan.startedAt,
      slots: <String, List<MovementSlot>>{
        for (final day in plan.slots.entries)
          day.key: <MovementSlot>[
            for (final s in day.value)
              if (s.id != slotId)
                s
              else
                MovementSlot(
                  id: s.id,
                  role: s.role,
                  movement: s.movement,
                  isMain: s.isMain,
                  sets: s.sets,
                  reps: s.reps,
                  lastTopKg: topKg,
                  lastTopReps: reps,
                  // Improved resets the count; held increments it. That counter
                  // is the whole rotation trigger, so getting it backwards
                  // would either rotate everything or nothing.
                  sessionsAtSameTop: improved ? 0 : s.sessionsAtSameTop + 1,
                ),
          ],
      },
    );
  }
}

/// Reasons a plan could not be read or written. Reuses [PlanFailure] rather
/// than inventing a parallel set, because the screens already handle it.
typedef StandingPlanException = PlanException;
