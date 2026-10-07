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

  // What is still to ask, and in which order, is [IntakeProgress] in
  // intake_flow.dart -- the one notion of "enough", living with the questions.
  // A `missing` list used to live here as well, in a different order (goal
  // first) and with a field the flow never asks (`which weekdays`). It was what
  // the coach was told to gather, so the coach asked one question while the
  // options under it answered another.

  /// The weekdays the plan runs on: the ones they named, or [daysPerWeek]
  /// spread across the week when they named none.
  ///
  /// **Named days are the exception, not the rule.** The options under the
  /// days question are counts — "3 days" — so most lifters never name a day,
  /// and this used to fall back to a fixed four-day week whatever the count
  /// was: three days asked for, four built. A day can still be moved to today
  /// from the plan, so a sensible spread costs nobody their Tuesday.
  ///
  /// Named days are cleaned on the way through — deduplicated, kept to 1–7,
  /// in week order — because they come from a model's reading of prose, and
  /// `lift.plans` refuses a plan of no days or more than seven.
  List<int> get weekdaysOrDefault {
    final named = <int>{
      for (final d in availableWeekdays ?? const <int>[])
        if (d >= 1 && d <= 7) d,
    }.toList()..sort();
    if (named.isNotEmpty) return named;
    return spreadWeekdays(daysPerWeek ?? 4);
  }

  /// [days] training days laid out with rest between them where the week
  /// allows it, Monday first. 1 is Monday, 7 is Sunday.
  static List<int> spreadWeekdays(int days) => switch (days.clamp(1, 7)) {
    1 => const <int>[1],
    2 => const <int>[1, 4],
    3 => const <int>[1, 3, 5],
    4 => const <int>[1, 2, 4, 5],
    5 => const <int>[1, 2, 3, 4, 5],
    6 => const <int>[1, 2, 3, 4, 5, 6],
    _ => const <int>[1, 2, 3, 4, 5, 6, 7],
  };

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
  const IntakeTurn({required this.reply, required this.extracted, this.asking});

  final String reply;
  final PlanIntake extracted;

  /// Which question [reply] asks, by [IntakeField] name — `days`, `equipment`,
  /// `injuries`, `goal` — or null when it asks none of them.
  ///
  /// **Said by the coach, because only the coach knows what it just asked.**
  /// The options under a question used to be chosen by the app from its own
  /// list while the coach chose its question from a different one, so the
  /// coach could ask about equipment above a row of goals. A string rather
  /// than the enum so this file does not import the flow that imports it.
  final String? asking;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  return null;
}
