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
/// A standing plan has no session rows to stamp, and since #4 a finished
/// workout writes nothing back to it either. It was going to: `recordResult`
/// updated the slot a session came from with its top set and how long it had
/// been stuck. Nothing ever called it, and a slot's history is now read off
/// the log on the phone (`SlotHistory`), which works offline and cannot
/// disagree with what was lifted. So the store is: read the live one, and
/// replace it.
abstract interface class StandingPlanStore {
  /// The live plan, or null if there is not one.
  Future<StandingPlan?> active();

  /// The live plan as this phone can show it: the copy saved here at once,
  /// then the server's answer when it comes.
  ///
  /// **Saved first, server second** (#2). The plan used to be asked of the
  /// server first, with the saved copy only as the answer to an error — and on
  /// one bar of signal an error takes ten to thirty seconds to arrive, all of
  /// it spent on a Track with no session on it. A store with nothing saved has
  /// only the server's answer to give.
  Stream<PlanRead> watch();

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

  /// One answer, with no time on it: nothing here was ever on a server, so
  /// there is no sync to report.
  @override
  Stream<PlanRead> watch() async* {
    yield PlanRead(_plan, freshness: PlanFreshness.checked);
  }

  /// What the last [replace] was told, so a test can assert it was kept.
  PlanIntake? intake;

  @override
  Future<StandingPlan> replace(StandingPlan plan, {PlanIntake? intake}) async {
    calls.add('replace:${plan.id}');
    this.intake = intake;
    return _plan = plan;
  }
}

/// Where the plan on screen came from.
enum PlanFreshness {
  /// The copy saved on this phone, while the server is still being asked.
  saved,

  /// The server's answer, just now.
  checked,

  /// The copy saved on this phone, because the server did not answer.
  unreachable,
}

/// One answer from [StandingPlanStore.watch].
@immutable
class PlanRead {
  const PlanRead(this.plan, {required this.freshness, this.checkedAt});

  /// The plan, or null for none — no plan on the server, or nothing saved and
  /// no server to ask.
  final StandingPlan? plan;

  final PlanFreshness freshness;

  /// When the server last gave this answer. Null when it never has on this
  /// phone: a preview, a test, or nothing saved and no signal.
  final DateTime? checkedAt;
}

/// Reasons a plan could not be read or written. Reuses [PlanFailure] rather
/// than inventing a parallel set, because the screens already handle it.
typedef StandingPlanException = PlanException;
