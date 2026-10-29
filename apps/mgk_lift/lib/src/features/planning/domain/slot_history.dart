import 'package:meta/meta.dart';

import '../../stats/domain/training_stats.dart';
import '../../tracking/domain/session.dart';
import 'standing_plan.dart';

/// What a slot's movement has done, read off the log.
///
/// ## Derived, not stored
///
/// The slot was meant to keep this itself: `recordResult` on the plan store
/// wrote the top set and the stall count back to `lift.plan_slots` when a
/// workout finished. Nothing ever called it (#4), so every planned session
/// opened with no weight in it and "Pick a weight you could do N with
/// comfortably", nothing ever progressed, and nothing ever went stale.
///
/// Reading it off the log is the move saved workouts already made (D4 in
/// `docs/lift-2.0.0-logging-rework.md`, `seedWorkout`). The log is on the
/// phone, so it works with no signal and a session finished in a basement
/// counts the moment it is finished; a new plan has numbers on day one for
/// every movement this lifter has done before; and there is no second copy to
/// disagree with the log it would have been copied from. The columns on
/// `lift.plan_slots` are left as they are, unread and unwritten.
///
/// ## By movement, not by slot
///
/// Matched on name, case-insensitively, like everything else that reads the log
/// (`PreviousPerformance`, `TrainingStats.topSet`). Any finished session with
/// the movement in counts, planned or not: a bench is a bench. That also
/// settles a swap mid-session: the movement swapped in builds its own history
/// under its own name, and the slot's movement keeps its own.
@immutable
class SlotHistory {
  const SlotHistory({required this.top, required this.sessionsAtSameTop});

  /// Last time's top set: the heaviest working set of the most recent session
  /// that had one, and the most reps done at that weight.
  ///
  /// **Last time, not the best.** A lighter session is what was lifted last
  /// time, and the plan screen says so; the best is on the movement's screen.
  final TopSet top;

  /// How many sessions in a row the top set has not beaten the one before it,
  /// counting back from the latest. 0 is "it moved last time" — and is also a
  /// movement done once, where the weight was picked to be comfortable and the
  /// first increment is the obvious next step.
  final int sessionsAtSameTop;

  /// The history of [movement] in [log], or null when there is none.
  ///
  /// **Moved means beaten, by the rule a personal best uses** (ADR 0004):
  /// heavier, or as heavy for more reps. That is [TopSet.beats], the same
  /// comparison the summary makes, so a plan and a best cannot disagree about
  /// whether a lift moved. Matching last time is a hold. So is a lighter
  /// session: a light day is a light day rather than a regression to program
  /// around, so it counts toward a stall and is never read as going backwards.
  ///
  /// Each session's top set is [TrainingStats.topSet] over that session alone,
  /// which is what makes the rule the app's rather than this file's: finished
  /// sessions only, ticked working sets only, no warm-ups. A session where the
  /// movement has no such set — added and never done, warm-ups only, or
  /// bodyweight with no weight to have gone past — is not a session of it, and
  /// the count reaches past it to the one before.
  static SlotHistory? of(List<Session> log, String movement) {
    final tops = <TopSet>[
      for (final session in log)
        ?TrainingStats.topSet(<Session>[session], movement),
    ]..sort((a, b) => b.on.compareTo(a.on));
    if (tops.isEmpty) return null;

    var held = 0;
    while (held + 1 < tops.length && !tops[held].beats(tops[held + 1])) {
      held++;
    }
    return SlotHistory(top: tops.first, sessionsAtSameTop: held);
  }
}

/// [plan] with every slot's history read off [log]: what the plan screen
/// shows, and what today's session is prescribed from.
///
/// **One call for both.** "Last time 90 kg × 5" on the plan and the 92.5 a
/// session opens with are the same fact, and worked out in two places they
/// would disagree the first time one of them changed.
///
/// Whatever history the slots arrived with is replaced, not merged: the log is
/// the only source, so a slot it has nothing for has no history.
StandingPlan planWithHistory(StandingPlan plan, List<Session> log) =>
    StandingPlan(
      id: plan.id,
      name: plan.name,
      dayOrder: plan.dayOrder,
      weekdays: plan.weekdays,
      rationale: plan.rationale,
      startedAt: plan.startedAt,
      slots: <String, List<MovementSlot>>{
        for (final day in plan.slots.entries)
          day.key: <MovementSlot>[
            for (final slot in day.value) slotWithHistory(slot, log),
          ],
      },
    );

/// [slot] with its movement's history from [log]. See [planWithHistory].
MovementSlot slotWithHistory(MovementSlot slot, List<Session> log) {
  final history = SlotHistory.of(log, slot.movement);
  return MovementSlot(
    id: slot.id,
    role: slot.role,
    movement: slot.movement,
    isMain: slot.isMain,
    sets: slot.sets,
    reps: slot.reps,
    lastTopKg: history?.top.weight.kilograms,
    lastTopReps: history?.top.reps,
    sessionsAtSameTop: history?.sessionsAtSameTop ?? 0,
  );
}
