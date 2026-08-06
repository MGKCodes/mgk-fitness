import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_mappers.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';

void main() {
  group('intakeSlotsToContext', () {
    test('drops null slots and encodes metric wire values', () {
      final slots = IntakeSlots(
        goalDistanceMeters: 42195,
        eventDate: DateTime(2026, 11, 1),
        currentWeeklyMeters: 40000,
        availableWeekdays: const <int>{7, 1, 4},
        timeTrialDuration: const Duration(minutes: 22),
      );

      final ctx = intakeSlotsToContext(slots);

      expect(ctx['goal_distance_meters'], 42195);
      expect(ctx['event_date'], '2026-11-01');
      expect(ctx['current_weekly_meters'], 40000);
      expect(ctx['time_trial_seconds'], 22 * 60);
      // Sorted for a stable prompt prefix.
      expect(ctx['available_weekdays'], <int>[1, 4, 7]);
      // Unset slots are absent, not null.
      expect(ctx.containsKey('longest_recent_meters'), isFalse);
      expect(ctx.containsKey('days_per_week'), isFalse);
      expect(ctx.containsKey('injury_notes'), isFalse);
    });

    test('an empty profile produces an empty context', () {
      expect(intakeSlotsToContext(const IntakeSlots()), isEmpty);
    });
  });

  group('intakeSlotsFromExtracted', () {
    test('parses a full metric extraction into slots', () {
      final slots = intakeSlotsFromExtracted(<String, dynamic>{
        'goal_distance_meters': 21097.5,
        'event_date': '2026-12-06',
        'current_weekly_meters': 35000,
        'longest_recent_meters': 16000,
        'days_per_week': 4,
        'available_weekdays': <dynamic>[1, 3, 6, 7],
        'time_trial_distance_meters': 5000,
        'time_trial_seconds': 1320,
        'injury_notes': 'mild achilles',
      });

      expect(slots.goalDistanceMeters, 21097.5);
      expect(slots.eventDate, DateTime(2026, 12, 6));
      expect(slots.currentWeeklyMeters, 35000);
      expect(slots.longestRecentMeters, 16000);
      expect(slots.daysPerWeek, 4);
      expect(slots.availableWeekdays, <int>{1, 3, 6, 7});
      expect(slots.timeTrialDistanceMeters, 5000);
      expect(slots.timeTrialDuration, const Duration(seconds: 1320));
      expect(slots.injuryNotes, 'mild achilles');
    });

    test('nulls and missing keys become unset slots, not errors', () {
      final slots = intakeSlotsFromExtracted(<String, dynamic>{
        'goal_distance_meters': 10000,
        'event_date': null,
        'current_weekly_meters': null,
        // longest_recent_meters missing entirely
        'days_per_week': null,
        'available_weekdays': null,
        'injury_notes': '   ', // whitespace -> unset
      });

      expect(slots.goalDistanceMeters, 10000);
      expect(slots.eventDate, isNull);
      expect(slots.currentWeeklyMeters, isNull);
      expect(slots.longestRecentMeters, isNull);
      expect(slots.daysPerWeek, isNull);
      expect(slots.availableWeekdays, isNull);
      expect(slots.injuryNotes, isNull);
    });

    test('a malformed date degrades to unset rather than throwing', () {
      final slots = intakeSlotsFromExtracted(<String, dynamic>{
        'event_date': 'next tuesday',
      });
      expect(slots.eventDate, isNull);
    });

    test('extraction merges onto prior slots via IntakeSlots.merge', () {
      const base = IntakeSlots(goalDistanceMeters: 42195, daysPerWeek: 3);
      final extracted = intakeSlotsFromExtracted(<String, dynamic>{
        'current_weekly_meters': 40000,
        'days_per_week': 5, // overwrites
      });

      final merged = base.merge(extracted);

      expect(merged.goalDistanceMeters, 42195); // preserved
      expect(merged.currentWeeklyMeters, 40000); // added
      expect(merged.daysPerWeek, 5); // overwritten
    });
  });

  group('intakeTurnFromResponse', () {
    test('splits reply from extracted slots', () {
      final turn = intakeTurnFromResponse(<String, dynamic>{
        'reply': 'Great, a marathon in November. How much are you running now?',
        'extracted': <String, dynamic>{
          'goal_distance_meters': 42195,
          'event_date': '2026-11-01',
        },
      });

      expect(turn.reply, startsWith('Great, a marathon'));
      expect(turn.extracted.goalDistanceMeters, 42195);
      expect(turn.extracted.eventDate, DateTime(2026, 11, 1));
    });

    test('a missing extracted block degrades to an empty overlay', () {
      final turn = intakeTurnFromResponse(<String, dynamic>{
        'reply': 'What are you training for?',
      });

      expect(turn.reply, 'What are you training for?');
      // A runner who has said nothing needs asking what they want, not asking
      // for a goal distance they have not mentioned (ADR-0011).
      expect(turn.extracted.missingRequired, contains('intent'));
    });
  });
}
