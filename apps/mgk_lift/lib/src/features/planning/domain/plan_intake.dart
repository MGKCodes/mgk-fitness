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
