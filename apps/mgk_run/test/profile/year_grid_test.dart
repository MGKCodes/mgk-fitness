import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/training_history.dart';
import 'package:mgk_run/src/features/profile/presentation/year_grid.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// The year view: a shape you take in at a glance, and the two things that
/// stop it being one.
///
/// The first is orientation — weeks as columns, not rows — which is why this
/// exists beside `consistencyGrid` rather than replacing it. The second is that
/// shade means distance, so a year of short runs and a year of building to a
/// marathon do not draw the same picture.
void main() {
  // A Monday, so the last column is a fresh week with six days still to come.
  final monday = DateTime(2026, 8, 24, 15);

  RunSummary run(DateTime at, double meters) => RunSummary(
    startedAt: at,
    duration: const Duration(minutes: 30),
    distanceMeters: meters,
  );

  group('runYear', () {
    test('is weeks of seven, oldest first, Monday to Sunday', () {
      final weeks = runYear(runs: const <RunSummary>[], now: monday, weeks: 53);

      expect(weeks, hasLength(53));
      expect(weeks.every((w) => w.length == 7), isTrue);
      expect(weeks.first.first.date.weekday, DateTime.monday);
      expect(weeks.last.last.date.weekday, DateTime.sunday);
      // The last column contains today, because the year ends on it.
      expect(weeks.last.any((d) => d.isToday), isTrue);
    });

    test('two runs on one day are summed, not replaced', () {
      // A double, or a commute either side of a working day. Taking the longer
      // of the two would quietly under-report the week, and the year view is
      // the one surface where that would accumulate invisibly.
      final weeks = runYear(
        runs: <RunSummary>[
          run(DateTime(2026, 8, 20, 7), 5000),
          run(DateTime(2026, 8, 20, 18), 7000),
        ],
        now: monday,
      );
      final day = weeks
          .expand((w) => w)
          .firstWhere(
            (d) => d.date.year == 2026 && d.date.month == 8 && d.date.day == 20,
          );

      expect(day.meters, 12000);
      expect(day.ran, isTrue);
    });

    test('the rest of this week is future, which is not an absence', () {
      final weeks = runYear(runs: const <RunSummary>[], now: monday);
      final week = weeks.last;

      // Monday is today; Tuesday onward has not happened.
      expect(week[0].isToday, isTrue);
      expect(week[0].isFuture, isFalse);
      expect(week.skip(1).every((d) => d.isFuture), isTrue);
      // And a day that has not happened is not a day you failed to run.
      expect(week.skip(1).every((d) => d.ran), isFalse);
    });

    test('a run outside the window is not counted', () {
      final weeks = runYear(
        runs: <RunSummary>[run(DateTime(2020, 1, 1), 10000)],
        now: monday,
      );

      expect(weeks.expand((w) => w).any((d) => d.ran), isFalse);
    });
  });

  group('YearGrid', () {
    Future<void> pump(WidgetTester tester, List<RunSummary> runs) async {
      await tester.binding.setSurfaceSize(const Size(393, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: YearGrid(
              weeks: runYear(runs: runs, now: monday),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('names the days, so a row is identifiable', (tester) async {
      await pump(tester, <RunSummary>[run(DateTime(2026, 8, 19), 8000)]);

      // Three of seven. Without them the rows are anonymous stripes, and
      // "I never run on a Tuesday" is unreadable.
      expect(find.text('M'), findsOneWidget);
      expect(find.text('W'), findsOneWidget);
      expect(find.text('F'), findsOneWidget);
    });

    testWidgets('counts days run and their distance', (tester) async {
      await pump(tester, <RunSummary>[
        run(DateTime(2026, 8, 19), 8000),
        run(DateTime(2026, 8, 21), 12000),
      ]);

      expect(find.textContaining('2 days run'), findsOneWidget);
      expect(find.textContaining('20 km'), findsOneWidget);
    });

    testWidgets('says day, not days, for one', (tester) async {
      await pump(tester, <RunSummary>[run(DateTime(2026, 8, 19), 8000)]);

      // The same bug "1 runs over 8 weeks" was, on the sibling surface.
      expect(find.textContaining('1 day run'), findsOneWidget);
      expect(find.textContaining('1 days'), findsNothing);
    });

    testWidgets('holds the grid open before the first run', (tester) async {
      await pump(tester, const <RunSummary>[]);

      // The shape of the year is the promise, and a runner with nothing
      // recorded is exactly who is deciding whether the promise is worth
      // anything. No zero anywhere: a dash is an absence, a zero is a claim.
      expect(find.text('THE YEAR'), findsOneWidget);
      expect(find.textContaining('shows up here'), findsOneWidget);
      expect(find.textContaining('0 km'), findsNothing);
      expect(find.textContaining('0 days'), findsNothing);
    });

    testWidgets('carries a scale while nothing is selected', (tester) async {
      await pump(tester, <RunSummary>[run(DateTime(2026, 8, 19), 8000)]);

      // Shade means distance, which is not guessable — so it is stated.
      expect(find.text('Less'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });
  });
}
