/// What the runner has trained for before, derived rather than stored.
///
/// Every plan Runio has ever built for a runner is still on disk: `savePlan`
/// marks the old one `superseded` instead of deleting it, because a plan is a
/// record of what someone committed to. Nothing read them back, so a runner who
/// had been through two marathon blocks looked, to themselves and to their
/// coach, exactly like a runner who had just arrived.
///
/// **Everything here is computed from what is already stored.** No migration,
/// no new columns, and in particular no `supersededAt` — a plan stopped being
/// the active one at the moment the next plan was created, so an ordered list
/// of plans knows every plan's end date without being told. Storing it would
/// have been a second version of a fact the ordering already carries, and the
/// two would eventually disagree.
library;

import 'plan_shape.dart';

/// How a plan ended, as far as the record can tell.
enum PlanOutcome {
  /// The plan the runner is on now.
  current,

  /// Race day arrived while this was their plan. The strongest thing the record
  /// can say — it does not know whether they ran it, only that they got there
  /// still on the plan, which is most of what a coach wants to know.
  raced,

  /// Replaced before its race. Not a judgement: changing your mind about a race
  /// is ordinary, and so is getting injured.
  leftEarly,

  /// Ended with nothing to end at — a horizon or a rhythm, which have no date
  /// to arrive at and so cannot be raced or abandoned.
  ended,
}

/// One plan in the runner's history: what it was for, and what became of it.
///
/// Deliberately light. History does not need the skeleton — the arc of a block
/// the runner finished two years ago is not worth loading week by week — so this
/// carries the week *count* and no weeks.
class PlanRecord {
  const PlanRecord({
    required this.id,
    required this.startDate,
    required this.weeks,
    required this.isActive,
    this.goalDistanceMeters,
    this.eventDate,
    this.endedAt,
  });

  final String id;

  /// The Monday of week 1.
  final DateTime startDate;

  /// How many weeks the arc had.
  final int weeks;

  final bool isActive;
  final double? goalDistanceMeters;
  final DateTime? eventDate;

  /// When it stopped being the active plan — the creation date of whatever
  /// replaced it. Null for the current plan and for the oldest read of a
  /// history that has not been superseded.
  final DateTime? endedAt;

  PlanShape get shape {
    if (goalDistanceMeters == null) return PlanShape.rhythm;
    return eventDate == null ? PlanShape.horizon : PlanShape.block;
  }

  PlanOutcome get outcome {
    if (isActive) return PlanOutcome.current;
    final date = eventDate;
    // No date means nothing to arrive at, so neither raced nor abandoned.
    if (date == null) return PlanOutcome.ended;
    final end = endedAt;
    if (end == null) return PlanOutcome.ended;
    // Race day inside the plan's life: they got there still on it.
    return date.isBefore(end) ? PlanOutcome.raced : PlanOutcome.leftEarly;
  }

  /// Which week they were in when it ended, 1-based and clamped to the arc.
  ///
  /// The number that makes "they left a marathon block at week 9 of 16" sayable,
  /// which is the difference between a runner who has tried this before and one
  /// who has tried it before and stopped in the same place twice.
  int get weekReached {
    final end = endedAt;
    if (end == null) return weeks;
    final days = end.difference(startDate).inDays;
    if (days < 0) return 1;
    return (days ~/ 7 + 1).clamp(1, weeks);
  }

  /// True when they saw the arc through, whatever happened on the day.
  bool get wasSeenThrough =>
      outcome == PlanOutcome.raced || weekReached >= weeks;
}

/// A plan with the label the runner and the coach refer to it by.
class LabelledPlan {
  const LabelledPlan({required this.record, required this.label});

  final PlanRecord record;

  /// "Marathon plan 2", "Half marathon plan 1", "Keeping a rhythm".
  final String label;
}

/// The runner's plans, oldest first, each labelled.
///
/// **Numbered oldest-first on purpose, and that is the whole design.** A label
/// has to mean the same thing next month: if the newest marathon block were
/// "Marathon plan 1" then adding a plan would renumber every older one, and a
/// coach that said "you stopped Marathon plan 2 at week nine" would be pointing
/// at a different block by the time the runner asked about it. Counting up from
/// the first means a label is fixed the day it is earned.
///
/// Numbered *per distance*, because "your second marathon" is how people talk
/// about this and "your fifth plan" is not.
List<LabelledPlan> labelPlans(List<PlanRecord> oldestFirst) {
  final counts = <String, int>{};
  final out = <LabelledPlan>[];
  for (final record in oldestFirst) {
    final kind = _kindOf(record);
    final n = (counts[kind] ?? 0) + 1;
    counts[kind] = n;
    out.add(
      LabelledPlan(
        record: record,
        // A first plan of its kind is not "plan 1" — nobody says that until
        // there is a second. The number appears when it starts distinguishing.
        label: _labelFor(kind, n, _totalOf(oldestFirst, kind)),
      ),
    );
  }
  return out;
}

/// The runner's history as one line for the coach, or null when there is none.
///
/// Prose, not a struct, for the reason `CoachBrief` exists: a model handed a
/// list recites it. And only what bears on coaching them now — a runner who has
/// abandoned two marathon blocks at the same point is a different runner to
/// coach than one who has finished three, and that is the whole reason this is
/// in the brief at all.
String? planHistoryLine(
  List<LabelledPlan> history, {
  required String Function(double meters) distance,
}) {
  final past = history.where((p) => !p.record.isActive).toList();
  if (past.isEmpty) return null;

  final seenThrough = past.where((p) => p.record.wasSeenThrough).length;
  final left = past.where((p) => !p.record.wasSeenThrough).toList();

  final parts = <String>[];
  parts.add(
    past.length == 1
        ? 'They have trained with one plan before this.'
        : 'They have trained with ${past.length} plans before this.',
  );

  if (seenThrough > 0) {
    parts.add(
      seenThrough == 1
          ? 'They saw one of them through to the end.'
          : 'They saw $seenThrough of them through to the end.',
    );
  }

  // The specific one, when there is one worth naming. A runner who stopped
  // short is the case a coach should actually know about, and a week number is
  // what makes it usable rather than a shrug.
  if (left.isNotEmpty) {
    final worst = left.last.record;
    final goal = worst.goalDistanceMeters;
    final what = goal == null ? 'a plan' : 'a ${distance(goal)} block';
    parts.add(
      'Their most recent unfinished one was $what they stopped at week '
      '${worst.weekReached} of ${worst.weeks}. Do not bring this up unless it '
      'is relevant to what they are asking.',
    );
  }

  return parts.join(' ');
}

String _kindOf(PlanRecord record) {
  final goal = record.goalDistanceMeters;
  if (goal == null) return 'rhythm';
  // Bucketed to the nearest 100 m so a marathon entered as 42195 and one
  // entered as 42200 are the same runner's second marathon, not two firsts.
  return '${(goal / 100).round()}';
}

int _totalOf(List<PlanRecord> all, String kind) =>
    all.where((r) => _kindOf(r) == kind).length;

String _labelFor(String kind, int n, int total) {
  final base = kind == 'rhythm' ? 'Keeping a rhythm' : _nameFor(kind);
  // No number while it is the only one of its kind: "Marathon plan" reads
  // better than "Marathon plan 1" until there is a second to tell it from.
  return total == 1 ? base : '$base $n';
}

String _nameFor(String kind) {
  final meters = int.parse(kind) * 100;
  return switch (meters) {
    // The four distances people name rather than measure. Everything else is
    // said in kilometres, because "the 12.4 km plan" is what it is.
    >= 42000 && <= 42400 => 'Marathon plan',
    >= 21000 && <= 21200 => 'Half marathon plan',
    10000 => '10k plan',
    5000 => '5k plan',
    _ => '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)}k plan',
  };
}
