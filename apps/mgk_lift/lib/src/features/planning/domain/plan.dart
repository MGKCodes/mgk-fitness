import 'package:meta/meta.dart';
import 'package:mgk_units/mgk_units.dart';

import 'plan_validator.dart';

/// A training block, as the app thinks about it.
///
/// Mirrors `lift.plans` / `lift.plan_weeks` / `lift.plan_sessions`, and the
/// three levels exist for the same reason there: the arc is decided once and
/// the sessions are filled in a week at a time, so they are generated
/// separately and stored separately.
@immutable
class Plan {
  const Plan({
    required this.id,
    required this.startDate,
    required this.weeks,
    required this.status,
    required this.profile,
    this.goal,
    this.sessions = const <PlanSession>[],
    this.arc = const <PlanWeek>[],
  });

  final String id;
  final DateTime startDate;
  final int weeks;
  final PlanStatus status;

  /// What they said they are training for, in their words.
  final String? goal;

  /// Days, weekdays — what every generated week is checked against.
  final PlanProfile profile;

  final List<PlanWeek> arc;
  final List<PlanSession> sessions;

  bool get isActive => status == PlanStatus.active;

  /// Which week of the block a date falls in, 1-based, or null if outside it.
  int? weekOf(DateTime date) {
    final days = _midnight(date).difference(_midnight(startDate)).inDays;
    if (days < 0) return null;
    final week = days ~/ 7 + 1;
    return week > weeks ? null : week;
  }

  /// Today's session, if the plan has one. Null on a rest day, which is a
  /// legitimate and common answer rather than a gap.
  PlanSession? sessionOn(DateTime date) {
    final day = _midnight(date);
    for (final session in sessions) {
      if (_midnight(session.scheduledDate) == day) return session;
    }
    return null;
  }

  /// The next session at or after [date] that has not been done.
  ///
  /// Used by Track when today is a rest day: "nothing today, Thursday is
  /// pull" is a more useful thing to show than an empty card.
  PlanSession? nextFrom(DateTime date) {
    final day = _midnight(date);
    final upcoming =
        sessions
            .where(
              (s) =>
                  !_midnight(s.scheduledDate).isBefore(day) &&
                  s.status == PlanSessionStatus.planned,
            )
            .toList()
          ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  Plan copyWith({
    PlanStatus? status,
    List<PlanWeek>? arc,
    List<PlanSession>? sessions,
  }) => Plan(
    id: id,
    startDate: startDate,
    weeks: weeks,
    status: status ?? this.status,
    goal: goal,
    profile: profile,
    arc: arc ?? this.arc,
    sessions: sessions ?? this.sessions,
  );
}

/// `draft` until the lifter accepts it. A plan that went active the moment a
/// model produced it would be the app imposing training rather than proposing
/// it, which is why the state exists in the schema and not only in the UI.
enum PlanStatus {
  draft('draft'),
  active('active'),
  completed('completed'),
  superseded('superseded');

  const PlanStatus(this.wire);

  final String wire;

  static PlanStatus fromWire(String value) => values.firstWhere(
    (s) => s.wire == value,
    // An unknown status is not a plan anyone should be shown as live.
    orElse: () => PlanStatus.draft,
  );
}

/// One week of the arc: what it is for, before any session exists.
@immutable
class PlanWeek {
  const PlanWeek({required this.number, required this.phase, this.intent});

  final int number;
  final PlanPhase phase;

  /// What this week is for, in a sentence. Carries the block's shape from the
  /// call that laid it out to the call that fills it in.
  final String? intent;

  bool get isDeload => phase == PlanPhase.deload;
}

/// Run's fourth phase is `taper`, a race-week idea. Lifting's is `deload`,
/// which recurs every third or fourth week — a phase here, a boolean there.
enum PlanPhase {
  base('base'),
  build('build'),
  peak('peak'),
  deload('deload');

  const PlanPhase(this.wire);

  final String wire;

  /// What a lifter would call it.
  String get label => switch (this) {
    base => 'Base',
    build => 'Build',
    peak => 'Peak',
    deload => 'Deload',
  };

  static PlanPhase fromWire(String value) =>
      values.firstWhere((p) => p.wire == value, orElse: () => PlanPhase.base);
}

/// One planned session: a day, its movements, and what happened to it.
@immutable
class PlanSession {
  const PlanSession({
    required this.id,
    required this.weekNumber,
    required this.weekday,
    required this.scheduledDate,
    required this.movements,
    this.kind,
    this.rationale,
    this.status = PlanSessionStatus.planned,
    this.workoutId,
  });

  final String id;
  final int weekNumber;

  /// 1 = Monday through 7 = Sunday.
  final int weekday;
  final DateTime scheduledDate;

  /// `push`, `pull`, `legs`, `upper`, `lower`, `full-body`.
  final String? kind;

  final List<PlannedMovement> movements;

  /// Why this session looks like this, in the coach's words.
  final String? rationale;

  final PlanSessionStatus status;

  /// The logged session this became, once it has been trained. **This is what
  /// makes "did they do the plan" a join rather than a guess.**
  final String? workoutId;

  /// A name for the session, for the card and for the workout it becomes.
  String get title => switch (kind) {
    'push' => 'Push',
    'pull' => 'Pull',
    'legs' => 'Legs',
    'upper' => 'Upper',
    'lower' => 'Lower',
    'full-body' => 'Full body',
    _ => 'Session',
  };

  /// How many of its movements carry a number. Shown so a plan that is mostly
  /// targetless says so plainly rather than looking half-generated — which is
  /// the honest state for somebody a fortnight in.
  int get targetedMovements =>
      movements.where((PlannedMovement m) => m.target != null).length;

  PlanSession copyWith({
    PlanSessionStatus? status,
    String? workoutId,
    List<PlannedMovement>? movements,
  }) => PlanSession(
    id: id,
    weekNumber: weekNumber,
    weekday: weekday,
    scheduledDate: scheduledDate,
    kind: kind,
    movements: movements ?? this.movements,
    rationale: rationale,
    status: status ?? this.status,
    workoutId: workoutId ?? this.workoutId,
  );
}

enum PlanSessionStatus {
  planned('planned'),
  completed('completed'),
  skipped('skipped');

  const PlanSessionStatus(this.wire);

  final String wire;

  static PlanSessionStatus fromWire(String value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => PlanSessionStatus.planned,
  );
}

/// What the intake conversation gathered, and what the generator needs.
@immutable
class PlanIntake {
  const PlanIntake({
    this.goal,
    this.weeks,
    this.daysPerWeek,
    this.availableWeekdays,
    this.equipment,
    this.injuryNotes,
  });

  final String? goal;
  final int? weeks;
  final int? daysPerWeek;
  final List<int>? availableWeekdays;
  final String? equipment;
  final String? injuryNotes;

  /// Everything still unanswered, by name, so the next intake turn can be told
  /// what to ask for rather than working it out again.
  List<String> get missing => <String>[
    if (goal == null || goal!.trim().isEmpty) 'goal',
    if (daysPerWeek == null) 'days per week',
    if (availableWeekdays == null || availableWeekdays!.isEmpty)
      'which weekdays',
    if (equipment == null || equipment!.trim().isEmpty) 'equipment',
  ];

  /// Whether a block can be built from this.
  ///
  /// `weeks` and `injuryNotes` are deliberately not required: a lifter with no
  /// view on block length is normal (it defaults), and "nothing hurts" is an
  /// answer that leaves the field empty.
  bool get isComplete => missing.isEmpty;

  /// The default block length. Eight weeks is long enough to build and deload
  /// twice and short enough that somebody will actually finish one.
  static const int defaultWeeks = 8;

  int get weeksOrDefault => weeks ?? defaultWeeks;

  PlanIntake merge(PlanIntake next) => PlanIntake(
    goal: next.goal ?? goal,
    weeks: next.weeks ?? weeks,
    daysPerWeek: next.daysPerWeek ?? daysPerWeek,
    availableWeekdays: next.availableWeekdays ?? availableWeekdays,
    equipment: next.equipment ?? equipment,
    injuryNotes: next.injuryNotes ?? injuryNotes,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'goal': goal,
    'weeks': weeks,
    'days_per_week': daysPerWeek,
    'available_weekdays': availableWeekdays,
    'equipment': equipment,
    'injury_notes': injuryNotes,
  };

  static PlanIntake fromJson(Map<String, Object?> json) => PlanIntake(
    goal: (json['goal'] as String?)?.trim(),
    weeks: _int(json['weeks']),
    daysPerWeek: _int(json['days_per_week']),
    availableWeekdays: switch (json['available_weekdays']) {
      final List<Object?> days => <int>[
        for (final d in days)
          if (_int(d) case final int v) v,
      ],
      _ => null,
    },
    equipment: (json['equipment'] as String?)?.trim(),
    injuryNotes: (json['injury_notes'] as String?)?.trim(),
  );

  PlanProfile profileFor({bool isDeload = false}) => PlanProfile(
    daysPerWeek: daysPerWeek ?? 3,
    availableWeekdays: availableWeekdays ?? const <int>[1, 3, 5],
    isDeload: isDeload,
  );
}

/// One turn of the intake conversation.
@immutable
class IntakeTurn {
  const IntakeTurn({required this.reply, required this.extracted});

  final String reply;
  final PlanIntake extracted;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  return null;
}

DateTime _midnight(DateTime at) => DateTime(at.year, at.month, at.day);

/// A movement with a resolved target, rendered for a person.
extension PlannedMovementDisplay on PlannedMovement {
  /// `3 × 5 @ 85 kg`, or plain `3 × 8` when there is no number worth giving.
  ///
  /// The targetless form is not a degraded one. Most accessory work is
  /// programmed exactly like that, and a plan that padded it with a made-up
  /// weight to look complete would be worse in the way this whole path exists
  /// to prevent.
  String render(MassUnit unit) {
    final base = '$sets × $reps';
    final t = target;
    if (t == null) return base;
    final value = t.inDisplayUnit(unit);
    final rounded = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$base @ $rounded ${unit.isMetric ? 'kg' : 'lb'}';
  }
}
