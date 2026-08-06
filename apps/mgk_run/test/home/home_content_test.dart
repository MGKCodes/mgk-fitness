import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_note.dart';
import 'package:mgk_run/src/features/coaching/domain/training_history.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/session_labels.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// What Home says, once it stopped saying things twice.
void main() {
  group('the coach note leaves the charts to the charts', () {
    final now = DateTime(2026, 7, 30, 9);
    RunSummary run({required DateTime at, required double meters}) =>
        RunSummary(
          startedAt: at,
          duration: const Duration(minutes: 30),
          distanceMeters: meters,
        );

    test('a record still gets said — a chart cannot show one', () {
      final note = CoachNote.forRuns(<RunSummary>[
        run(at: now.subtract(const Duration(days: 9)), meters: 5000),
        run(at: now.subtract(const Duration(days: 1)), meters: 21000),
      ], now: now);
      expect(note?.kind, CoachNoteKind.record);
    });

    test('volume and consistency do not, because Home draws them', () {
      // Eight runs, no personal best among them. This once produced "Strong
      // month" directly above a chart of the same month (ADR-0017).
      final flat = <RunSummary>[
        for (var d = 1; d <= 8; d++)
          run(at: now.subtract(Duration(days: d)), meters: 8000),
      ];
      expect(CoachNote.forRuns(flat, now: now), isNull);
    });
  });

  group('a session is called what the runner calls it', () {
    test("the runner's own word wins over the kind", () {
      const parkrun = PlannedSession(
        weekday: DateTime.saturday,
        kind: SessionKind.timeTrial,
        distanceMeters: 5000,
        label: 'parkrun',
      );
      expect(sessionName(parkrun), 'parkrun');
      expect(
        sessionName(parkrun),
        isNot(contains('Time trial')),
        reason: 'renaming the thing they already do is what label prevents',
      );
    });

    test('and the kind stands in where they never named it', () {
      const easy = PlannedSession(
        weekday: DateTime.tuesday,
        kind: SessionKind.easy,
        distanceMeters: 8000,
      );
      expect(sessionName(easy), 'Easy');
    });
  });

  group('the next run in the week', () {
    TrainingWeek weekOf(List<int> days) => TrainingWeek(
      skeletonIndex: 1,
      sessions: <PlannedSession>[
        for (final d in days)
          PlannedSession(
            weekday: d,
            kind: SessionKind.easy,
            distanceMeters: 8000,
          ),
      ],
    );

    test('is the soonest one after today, so a rest day looks forward', () {
      final week = weekOf(<int>[1, 4, 7]);
      expect(nextRunAfter(week, DateTime.tuesday)?.weekday, DateTime.thursday);
    });

    test('is null once the rest of the week is rest', () {
      // Rather than reaching into next week, which is not generated yet.
      final week = weekOf(<int>[1, 4]);
      expect(nextRunAfter(week, DateTime.friday), isNull);
    });

    test('never offers today as what is next', () {
      final week = weekOf(<int>[3, 6]);
      expect(
        nextRunAfter(week, DateTime.wednesday)?.weekday,
        DateTime.saturday,
      );
    });
  });
}
