import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/coaching/domain/training_standing.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/profile/presentation/profile_screen.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// The training log lives on this page rather than on one of its own, so the
/// behaviour the old history screen was tested for is tested here: the runs
/// list and a tap that opens one.
///
/// The other half of these tests is the page a runner sees *before* any of that
/// exists. An empty profile has to read as new rather than as broken, which
/// means showing the structure it is going to fill — and showing it without
/// stating a single figure the app has not measured.
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
    VoidCallback? onAddRun,
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
          onAddRun: onAddRun,
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

  group('before the first run', () {
    // The standing the shell really passes for an empty log, rather than one
    // written for the test: the copy on this card is the coach's, and a test
    // that invented its own would stop noticing when the coach's changed.
    final nothingYet = TrainingStanding.read(runs: const <RunSummary>[]);

    testWidgets('the stat structure is on screen, held open', (tester) async {
      await pump(tester, log: const <RunSummary>[], standing: nothingYet);

      // The lifetime figure and the three under it.
      expect(find.text('LIFETIME'), findsOneWidget);
      expect(find.text('— km'), findsOneWidget);
      expect(find.text('RUNS'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('STREAK'), findsOneWidget);

      // The two bests the app keeps, named before there is one to put in them.
      expect(find.text('RECORDS'), findsOneWidget);
      expect(find.text('LONGEST RUN'), findsOneWidget);
      expect(find.text('FASTEST PACE'), findsOneWidget);

      // The log, headed, with the shape of a run row beneath it — so the
      // promise reaches the level a runner reads their training at.
      expect(find.text('YOUR RUNS'), findsOneWidget);
      expect(find.text('Date  ·  time  ·  pace'), findsNWidgets(2));

      // And one line saying what to do about all of it.
      expect(find.textContaining('Record your first run'), findsOneWidget);
    });

    testWidgets('it states no number it has not earned', (tester) async {
      await pump(tester, log: const <RunSummary>[], standing: nothingYet);

      // A zero is a claim and a dash is an absence. "0.0 km", "0 runs",
      // "0:00 /km" are figures this app has never measured, and a runner
      // cannot tell an unearned number from a wrong one — which is how an
      // empty page starts reading as a broken one.
      final numerals = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .where((String text) => RegExp(r'\d').hasMatch(text))
          .toList();

      expect(
        numerals,
        isEmpty,
        reason: 'digits on an empty profile: $numerals',
      );
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('nothing on it pretends to be a control', (tester) async {
      await pump(tester, log: const <RunSummary>[], standing: nothingYet);

      // A placeholder row wearing a chevron offers to open a run that does not
      // exist, and "newest first" describes the order of nothing.
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.text('Newest first'), findsNothing);
    });

    testWidgets('the held-open figures are in the runner unit', (tester) async {
      await pump(
        tester,
        log: const <RunSummary>[],
        standing: nothingYet,
        unit: UnitSystem.imperial,
      );

      expect(find.text('— mi'), findsOneWidget);
      expect(find.textContaining('km'), findsNothing);
    });

    testWidgets('the coach has a place on the page from day one', (
      tester,
    ) async {
      await pump(tester, log: const <RunSummary>[], standing: nothingYet);

      // Hidden until now, on the grounds that its empty copy repeated the card
      // above it. A new runner could not tell that anything was ever going to
      // read their training.
      expect(find.text('YOUR COACH'), findsOneWidget);
      expect(find.text('Nothing recorded yet'), findsOneWidget);
    });

    testWidgets('a run the phone did not record can still be added', (
      tester,
    ) async {
      var added = false;
      await pump(
        tester,
        log: const <RunSummary>[],
        standing: nothingYet,
        onAddRun: () => added = true,
      );

      // Somebody who ran this morning without the app has a run to enter, and
      // the affordance used to be hidden behind already having recorded one.
      await tester.tap(find.text('Add a run'));
      await tester.pump();

      expect(added, isTrue);
    });
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
