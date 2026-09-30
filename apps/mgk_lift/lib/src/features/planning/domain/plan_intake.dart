import 'package:meta/meta.dart';

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

  /// Everything still unanswered, by name, **for the coach** — sent with every
  /// intake turn so the model is told what to gather rather than working it
  /// out from the transcript again.
  ///
  /// This is not the screen's gate, and the difference matters. `missing` is
  /// what the coach should still try to extract, including `which weekdays`,
  /// which has no question of its own because it falls out of prose — "Mon,
  /// Wed, Fri" answers it and "3 days" does not. What the lifter is *asked*,
  /// and when the app decides it has enough, is [IntakeProgress] in
  /// intake_flow.dart.
  ///
  /// There used to be an `isComplete` here as well, reading `missing.isEmpty`,
  /// and it was the screen's gate. It disagreed with the flow in both
  /// directions: it demanded a goal the flow calls skippable, and it demanded
  /// weekdays that the one caller of this whole model — `LiftShell._buildPlan`
  /// — already defaults when they are absent. So a lifter could answer every
  /// question the coach asked, watch the bar fill, and never see the button.
  /// One notion of "enough", and it lives with the questions.
  List<String> get missing => <String>[
    if (goal == null || goal!.trim().isEmpty) 'goal',
    if (daysPerWeek == null) 'days per week',
    if (availableWeekdays == null || availableWeekdays!.isEmpty)
      'which weekdays',
    if (equipment == null || equipment!.trim().isEmpty) 'equipment',
  ];

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
