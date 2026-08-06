import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/core/units/unit_system.dart';
import 'package:mgk_run/src/features/coaching/domain/training_standing.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/profile/presentation/profile_screen.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// The training log lives on this page rather than on one of its own, so the
/// behaviour the old history screen was tested for is tested here: the runs
/// list, a tap opens one, and an empty log says so rather than showing a header
/// over nothing.
void main() {
  final runs = <RunSummary>[
    RunSummary(
      startedAt: DateTime(2026, 7, 21, 7, 32),
      duration: const Duration(minutes: 27, seconds: 45),
      distanceMeters: 5230,
      avgPaceSecondsPerKm: 318,
    ),
    RunSummary(
      startedAt: DateTime(2026, 7, 18, 8),
      duration: const Duration(minutes: 54),
      distanceMeters: 10000,
      avgPaceSecondsPerKm: 324,
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required List<RunSummary> log,
    void Function(RunSummary run)? onOpenRun,
    void Function(String opener)? onAskCoach,
    TrainingStanding? standing,
    UnitSystem unit = UnitSystem.metric,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ProfileScreen(
          stats: RunnerStats.from(log),
          runs: log,
          standing: standing,
          unit: unit,
          onOpenRun: onOpenRun,
          onAskCoach: onAskCoach,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the totals and the log they are derived from', (
    tester,
  ) async {
    await pump(tester, log: runs);

    // The lifetime total leads the page; the account facts that used to head
    // it are in Settings now and must not have followed the log here.
    expect(find.textContaining('15.2'), findsOneWidget); // 5.23 + 10 km
    expect(find.text('dev@runio.app'), findsNothing);
    expect(find.textContaining('since'), findsNothing);

    // The log itself, headed by its count and its order.
    expect(find.text('2 RUNS'), findsOneWidget);
    expect(find.text('Newest first'), findsOneWidget);
    expect(find.text('5.23 km'), findsOneWidget);
    expect(find.text('10.00 km'), findsOneWidget);
  });

  testWidgets('opens a run on tap', (tester) async {
    RunSummary? opened;
    await pump(tester, log: runs, onOpenRun: (run) => opened = run);

    await tester.tap(find.text('5.23 km'));
    await tester.pump();

    expect(opened, same(runs.first));
  });

  testWidgets('renders the log in the display unit', (tester) async {
    await pump(tester, log: runs, unit: UnitSystem.imperial);

    expect(find.textContaining('km'), findsNothing);
    expect(find.textContaining('mi'), findsWidgets);
  });

  testWidgets('an empty log gets an invitation, not a header over nothing', (
    tester,
  ) async {
    await pump(tester, log: const <RunSummary>[]);

    expect(find.text('No runs yet'), findsOneWidget);
    expect(find.text('Newest first'), findsNothing);
    expect(find.textContaining('RUNS'), findsNothing);
  });

  testWidgets('the count reads as one for a single run', (tester) async {
    await pump(tester, log: <RunSummary>[runs.first]);

    expect(find.text('1 RUN'), findsOneWidget);
  });

  testWidgets('the coach card carries the standing and hands off a question', (
    tester,
  ) async {
    String? asked;
    await pump(
      tester,
      log: runs,
      standing: const TrainingStanding(
        headline: 'Running more than you were',
        detail: '44.2 km in the last four weeks, up from 31.0 the four before.',
        verdict: StandingVerdict.building,
      ),
      onAskCoach: (opener) => asked = opener,
    );

    expect(find.text('YOUR COACH'), findsOneWidget);
    expect(find.text('Running more than you were'), findsOneWidget);
    expect(
      find.text(
        '44.2 km in the last four weeks, up from 31.0 the four before.',
      ),
      findsOneWidget,
    );

    // The whole card is the target: a statement about the runner is the thing
    // they want to take up with someone.
    await tester.tap(find.text('Running more than you were'));
    await tester.pump();

    // A question, not a blank dock: the conversation should open where the
    // card left off rather than on something the runner has to think of.
    expect(asked, isNotNull);
    expect(asked, isNotEmpty);
  });

  testWidgets('with no coach configured there is no dead control', (
    tester,
  ) async {
    await pump(
      tester,
      log: runs,
      standing: const TrainingStanding(
        headline: 'Running more than you were',
        detail: 'More than the four weeks before.',
        verdict: StandingVerdict.building,
      ),
    );

    expect(find.text('Running more than you were'), findsOneWidget);
    expect(find.text('Ask about this'), findsNothing);
  });
}
