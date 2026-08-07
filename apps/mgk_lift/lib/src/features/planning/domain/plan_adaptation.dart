import 'package:meta/meta.dart';

import 'package:mgk_units/mgk_units.dart';

import 'plan.dart';
import 'plan_validator.dart';

/// A change the coach proposes to the week ahead.
///
/// **A diff, not a plan.** Regenerating the week would rewrite sessions the
/// lifter has already trained, lose what actually happened, and make "move
/// Thursday" indistinguishable from starting the block again. A list of
/// targeted changes leaves everything it does not mention exactly as it was —
/// which is the only way the plan stays a record of what was prescribed.
enum PlanChangeKind {
  move('move'),
  lighten('lighten'),
  drop('drop'),
  swapMovement('swap_movement');

  const PlanChangeKind(this.wire);

  final String wire;

  static PlanChangeKind? fromWire(String value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    // Unknown means a model invented an action. Dropping it is safer than
    // guessing which of the four it meant.
    return null;
  }
}

@immutable
class PlanChange {
  const PlanChange({
    required this.kind,
    required this.weekday,
    required this.why,
    this.toWeekday,
    this.movement,
    this.to,
  });

  final PlanChangeKind kind;

  /// Which session this changes. 1 = Monday through 7 = Sunday.
  final int weekday;

  /// One short line, shown to the lifter beside it.
  final String why;

  final int? toWeekday;
  final String? movement;
  final String? to;

  /// What this reads as on the approval sheet.
  String label(PlanSession session) => switch (kind) {
    PlanChangeKind.move =>
      'Move ${session.title} to ${_weekdayName(toWeekday ?? 0)}',
    PlanChangeKind.lighten => 'Go lighter on ${session.title}',
    PlanChangeKind.drop => 'Drop ${session.title}',
    PlanChangeKind.swapMovement => '$movement → $to',
  };

  static PlanChange? fromJson(Map<String, Object?> json) {
    final kind = PlanChangeKind.fromWire(json['action'] as String? ?? '');
    if (kind == null) return null;
    final weekday = _int(json['weekday']);
    if (weekday == null) return null;
    return PlanChange(
      kind: kind,
      weekday: weekday,
      why: (json['why'] as String? ?? '').trim(),
      toWeekday: _int(json['to_weekday']),
      movement: (json['movement'] as String?)?.trim(),
      to: (json['to'] as String?)?.trim(),
    );
  }
}

/// What the coach said, and what it wants to change.
@immutable
class AdaptProposal {
  const AdaptProposal({
    required this.reply,
    this.changes = const <PlanChange>[],
  });

  final String reply;
  final List<PlanChange> changes;

  static AdaptProposal fromJson(Map<String, Object?> json) {
    final raw = json['changes'];
    return AdaptProposal(
      reply: (json['reply'] as String? ?? '').trim(),
      changes: <PlanChange>[
        if (raw is List)
          for (final c in raw)
            if (c is Map<String, Object?>)
              if (PlanChange.fromJson(c) case final PlanChange change) change,
      ],
    );
  }
}

/// Checks proposed changes against the plan, and applies the ones the lifter
/// keeps.
///
/// Unusable changes are **dropped, not rejected**, the same trade a mid-session
/// swap makes: the reply is the valuable part, and refusing the whole answer
/// because one of three suggestions named a day they do not train would be the
/// worst reading of "the validator disposes".
@immutable
class PlanAdapter {
  const PlanAdapter();

  /// The changes worth showing, with the session each one touches.
  ///
  /// A change is dropped when it names a session that is not in the week, one
  /// that is **already done**, a destination the lifter does not train on or
  /// that is already taken, or a movement the session does not contain.
  List<AdaptChange> check(
    AdaptProposal proposal, {
    required Plan plan,
    required int weekNumber,
  }) {
    final week =
        plan.sessions
            .where((PlanSession s) => s.weekNumber == weekNumber)
            .toList()
          ..sort((a, b) => a.weekday.compareTo(b.weekday));
    final taken = <int>{for (final s in week) s.weekday};

    final kept = <AdaptChange>[];
    for (final change in proposal.changes) {
      final session = week
          .where((PlanSession s) => s.weekday == change.weekday)
          .firstOrNull;
      if (session == null) continue;

      // A session that has been trained is a record, not a draft. Editing it
      // would make the lifter's log disagree with what they actually did.
      if (session.status != PlanSessionStatus.planned) continue;

      switch (change.kind) {
        case PlanChangeKind.move:
          final to = change.toWeekday;
          if (to == null ||
              !plan.profile.availableWeekdays.contains(to) ||
              taken.contains(to)) {
            continue;
          }
        case PlanChangeKind.swapMovement:
          final from = change.movement;
          if (from == null ||
              change.to == null ||
              change.to!.isEmpty ||
              !session.movements.any(
                (PlannedMovement m) =>
                    m.name.toLowerCase() == from.toLowerCase(),
              )) {
            continue;
          }
        case PlanChangeKind.lighten:
        case PlanChangeKind.drop:
          break;
      }

      kept.add(AdaptChange(change: change, session: session));
    }
    return kept;
  }

  /// Applies the accepted changes and returns the new plan.
  ///
  /// Everything not named is returned untouched — including every session in
  /// every other week, which is the whole reason this takes a diff.
  Plan apply(Plan plan, List<AdaptChange> accepted) {
    var sessions = plan.sessions;

    for (final accept in accepted) {
      final change = accept.change;
      sessions = <PlanSession>[
        for (final session in sessions)
          if (session.id != accept.session.id)
            session
          else
            ...switch (change.kind) {
              // Dropping removes the session outright rather than marking it
              // skipped: they did not skip it, it was never asked of them.
              PlanChangeKind.drop => const <PlanSession>[],
              PlanChangeKind.move => <PlanSession>[
                _moved(session, change.toWeekday!),
              ],
              PlanChangeKind.lighten => <PlanSession>[_lightened(session)],
              PlanChangeKind.swapMovement => <PlanSession>[
                _swapped(session, change.movement!, change.to!),
              ],
            },
      ];
    }

    return plan.copyWith(sessions: sessions);
  }

  static PlanSession _moved(PlanSession session, int weekday) => PlanSession(
    id: session.id,
    weekNumber: session.weekNumber,
    weekday: weekday,
    scheduledDate: session.scheduledDate.add(
      Duration(days: weekday - session.weekday),
    ),
    kind: session.kind,
    movements: session.movements,
    rationale: session.rationale,
    status: session.status,
    workoutId: session.workoutId,
  );

  /// One set off every movement, and the top set eased.
  ///
  /// Done in Dart rather than asked of the model for the same reason targets
  /// are: it is arithmetic on their own numbers, and a model asked to restate a
  /// whole session to make it lighter will change more than it was asked to.
  static PlanSession _lightened(PlanSession session) => session.copyWith(
    movements: <PlannedMovement>[
      for (final m in session.movements)
        PlannedMovement(
          name: m.name,
          sets: m.sets > 1 ? m.sets - 1 : m.sets,
          reps: m.reps,
          note: m.note,
          target: m.target == null
              ? null
              : _round(m.target!.kilograms * _lightenFactor),
        ),
    ],
  );

  /// Ten per cent off, rounded back to a loadable weight.
  static const double _lightenFactor = 0.9;

  static Mass? _round(double kilograms) {
    final rounded = (kilograms / 2.5).round() * 2.5;
    return rounded < 2.5 ? null : Mass.kilograms(rounded);
  }

  static PlanSession _swapped(PlanSession session, String from, String to) =>
      session.copyWith(
        movements: <PlannedMovement>[
          for (final m in session.movements)
            if (m.name.toLowerCase() == from.toLowerCase())
              // The replacement carries no target: it is a movement the coach
              // has not seen this lifter do, which is exactly the case the load
              // rule exists for.
              PlannedMovement(name: to, sets: m.sets, reps: m.reps)
            else
              m,
        ],
      );
}

/// A change that survived checking, with the session it touches.
@immutable
class AdaptChange {
  const AdaptChange({required this.change, required this.session});

  final PlanChange change;
  final PlanSession session;

  String get label => change.label(session);
  String get why => change.why;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  return null;
}

String _weekdayName(int weekday) => switch (weekday) {
  1 => 'Monday',
  2 => 'Tuesday',
  3 => 'Wednesday',
  4 => 'Thursday',
  5 => 'Friday',
  6 => 'Saturday',
  7 => 'Sunday',
  _ => 'another day',
};
