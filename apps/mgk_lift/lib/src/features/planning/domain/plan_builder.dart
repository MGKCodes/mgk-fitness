import 'package:meta/meta.dart';

import 'plan.dart';
import 'plan_shape.dart';
import 'plan_template.dart';
import 'standing_plan.dart';
import 'training_split.dart';

/// What `lift_plan` came back with, before anything has checked it.
@immutable
class PlanProposal {
  const PlanProposal({
    required this.reply,
    required this.name,
    required this.days,
  });

  /// A sentence or two for the lifter on why this shape suits them. Shown under
  /// the plan; written by the coach because it is the part a template could
  /// never do well.
  final String reply;

  /// What the coach called it. Free text — see [StandingPlan.name].
  final String name;

  final List<ProposedDay> days;

  static PlanProposal fromJson(Map<String, Object?> json) => PlanProposal(
    reply: (json['reply'] as String? ?? '').trim(),
    name: (json['name'] as String? ?? '').trim(),
    days: <ProposedDay>[
      for (final d in (json['days'] as List?) ?? const [])
        if (d is Map<String, Object?>) ProposedDay.fromJson(d),
    ],
  );
}

@immutable
class ProposedDay {
  const ProposedDay({required this.day, required this.movements});

  final String day;
  final List<ProposedMovement> movements;

  static ProposedDay fromJson(Map<String, Object?> json) => ProposedDay(
    day: (json['day'] as String? ?? '').trim(),
    movements: <ProposedMovement>[
      for (final m in (json['movements'] as List?) ?? const [])
        if (m is Map<String, Object?>) ProposedMovement.fromJson(m),
    ],
  );
}

@immutable
class ProposedMovement {
  const ProposedMovement({
    required this.role,
    required this.movement,
    required this.isMain,
    required this.sets,
    required this.reps,
  });

  final String role;
  final String movement;
  final bool isMain;
  final int sets;
  final int reps;

  static ProposedMovement fromJson(Map<String, Object?> json) =>
      ProposedMovement(
        role: (json['role'] as String? ?? '').trim(),
        movement: (json['movement'] as String? ?? '').trim(),
        isMain: json['is_main'] as bool? ?? false,
        // Defaulted rather than rejected. A missing set count is a plan worth
        // checking rather than one worth throwing away, and PlanShape will say
        // so if the volume comes out wrong.
        sets: (json['sets'] as num?)?.toInt() ?? 3,
        reps: (json['reps'] as num?)?.toInt() ?? 10,
      );
}

/// Builds a plan: ask the coach, check it, ask again, fall back.
///
/// ## Why there is a loop at all
///
/// The coach is free to invent the shape of the week — that is the whole point
/// of it being a model rather than a template. [PlanShape] is what makes that
/// safe: it checks what a plan DOES rather than which template it resembles, so
/// a proposal that trains legs once, stacks two hard sessions back to back, or
/// names a movement that does not exist comes back with instructions rather
/// than being shown.
///
/// Violations are handed back verbatim, which is the shape the block generator
/// already used and the reason they are written as instructions.
///
/// ## Why the loop is short
///
/// One retry. A model that has been told exactly what was wrong and gets it
/// wrong again is not going to be talked round on the third attempt, and
/// somebody is waiting. The fallback is a template that clears the same checks,
/// so the failure mode is a duller plan rather than no plan.
class PlanBuilder {
  const PlanBuilder({required this.propose, this.now});

  /// Calls `lift_plan`. Given the violations from the previous attempt, if any.
  final Future<PlanProposal> Function({
    required PlanIntake intake,
    required List<int> weekdays,
    required List<String> catalogue,
    List<String> violations,
  })
  propose;

  final DateTime? now;

  /// Attempts, including the first. Two: see the class doc.
  static const int attempts = 2;

  Future<BuiltPlan> build({
    required String id,
    required PlanIntake intake,
    required List<int> weekdays,
    required List<String> catalogue,
    Equipment equipment = Equipment.fullGym,
    Set<String> avoidRoles = const <String>{},
  }) async {
    var violations = const <String>[];

    for (var attempt = 0; attempt < attempts; attempt++) {
      final PlanProposal proposal;
      try {
        proposal = await propose(
          intake: intake,
          weekdays: weekdays,
          catalogue: catalogue,
          violations: violations,
        );
      } on Object {
        // The coach being unreachable is not a reason to leave somebody without
        // a plan. Straight to the floor.
        return BuiltPlan(
          plan: _fallback(id, weekdays, equipment, avoidRoles),
          fromCoach: false,
          violations: const <String>['coach unavailable'],
        );
      }

      final plan = _hydrate(id, proposal, weekdays);
      violations = PlanShape.violations(plan, avoidRoles: avoidRoles);
      if (violations.isEmpty) {
        return BuiltPlan(plan: plan, fromCoach: true);
      }
    }

    return BuiltPlan(
      plan: _fallback(id, weekdays, equipment, avoidRoles),
      fromCoach: false,
      violations: violations,
    );
  }

  StandingPlan _hydrate(String id, PlanProposal p, List<int> weekdays) {
    final slots = <String, List<MovementSlot>>{};
    for (final (i, d) in p.days.indexed) {
      // Days repeat by design — an Upper/Lower week has two 'Upper' days — so
      // a repeated name is merged rather than overwritten, and the FIRST
      // occurrence wins. A coach that describes the same day twice with
      // different movements has contradicted itself, and taking the later one
      // would silently prefer whichever it wrote last.
      slots.putIfAbsent(
        d.day,
        () => <MovementSlot>[
          for (final (j, m) in d.movements.indexed)
            MovementSlot(
              id: '$id-$i-$j',
              role: m.role,
              movement: m.movement,
              isMain: m.isMain,
              sets: m.sets,
              reps: m.reps,
            ),
        ],
      );
    }

    return StandingPlan(
      id: id,
      name: p.name.isEmpty ? 'Your plan' : p.name,
      dayOrder: <String>[for (final d in p.days) d.day],
      rationale: p.reply.isEmpty ? null : p.reply,
      weekdays: weekdays,
      startedAt: now ?? DateTime.now(),
      slots: slots,
    );
  }

  StandingPlan _fallback(
    String id,
    List<int> weekdays,
    Equipment equipment,
    Set<String> avoidRoles,
  ) {
    final split = TrainingSplit.forDays(weekdays.length);
    return StandingPlan(
      id: id,
      name: split.name,
      dayOrder: split.weekFor(weekdays.length),
      rationale: split.why,
      weekdays: weekdays,
      startedAt: now ?? DateTime.now(),
      slots: PlanTemplate.slotsFor(
        split: split,
        days: weekdays.length,
        equipment: equipment,
        avoid: avoidRoles,
      ),
    );
  }
}

/// A plan, and how it was arrived at.
///
/// **Whether the coach wrote it is worth keeping.** A fallback plan is a
/// perfectly good week and a worse product: it knows nothing about this
/// person's history, weak points or preferences. Somebody who got one because a
/// provider was down should be able to ask for another go, and the app cannot
/// offer that if it does not know which it gave them.
@immutable
class BuiltPlan {
  const BuiltPlan({
    required this.plan,
    required this.fromCoach,
    this.violations = const <String>[],
  });

  final StandingPlan plan;
  final bool fromCoach;

  /// Why the coach's attempts were rejected, when they were. Empty on success.
  /// Kept for the log rather than the lifter — "your plan was rejected for
  /// training legs once" is not their problem to solve.
  final List<String> violations;
}
