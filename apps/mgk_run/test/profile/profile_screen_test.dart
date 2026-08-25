import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/coaching/domain/training_standing.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/profile/presentation/profile_screen.dart';
import 'package:mgk_run/src/features/recording/domain/best_effort.dart';
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
    // Pins the clock the streak and the year grid are read against. Without it
    // a test that counts the dashes on the page passes or fails depending on
    // what day it is run: a lapsed streak renders one too, and whether a fixed
    // fixture has lapsed is a question about today.
    DateTime? now,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ProfileScreen(
          stats: RunnerStats.from(log, now: now),
          runs: log,
          now: now,
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

      // The bests the app keeps, named before there is one to put in them.
      expect(find.text('RECORDS'), findsOneWidget);
      expect(find.text('LONGEST RUN'), findsOneWidget);
      expect(find.text('FASTEST PACE'), findsOneWidget);

      // Including all four race distances. A runner who has never run 10 km
      // sees the 10K row, empty — the row names a distance, it does not claim
      // a time, and naming them is how somebody with nothing recorded learns
      // what this section is going to hold.
      expect(find.text('5K'), findsOneWidget);
      expect(find.text('10K'), findsOneWidget);
      expect(find.text('HALF MARATHON'), findsOneWidget);
      expect(find.text('MARATHON'), findsOneWidget);

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
      //
      // **Values only, not labels**, and the distinction had to be drawn once
      // the records section started naming distances: "5K" and "10K" carry
      // digits and claim nothing, because a heading saying which record a slot
      // is for is not the app reporting a measurement. Every label on this page
      // is a [SectionLabel] and every figure is a plain [Text], so the split is
      // structural rather than a list of strings to keep updating.
      final labels = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(SectionLabel),
              matching: find.byType(Text),
            ),
          )
          .toSet();
      final numerals = tester
          .widgetList<Text>(find.byType(Text))
          .where((Text t) => !labels.contains(t))
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

  group('records at the standard distances', () {
    /// The Monday after the 23 Aug run, so the streak is live and the page
    /// carries no dash but the ones the records section puts there.
    final monday = DateTime(2026, 8, 24, 15);

    /// The 23 Aug test run: 10.18 km in 58:28, whose actual 10K — the fastest
    /// continuous 10 km inside it — was 57:25. The gap between those two
    /// numbers is the entire reason a record is searched for rather than read
    /// off the summary (ADR-0026).
    final tenK = RunSummary(
      startedAt: DateTime(2026, 8, 23, 14, 2),
      duration: const Duration(minutes: 58, seconds: 28),
      distanceMeters: 10180,
      bestEfforts: const <BestEffort>[
        BestEffort(
          distanceMeters: 5000,
          duration: Duration(minutes: 27, seconds: 41),
        ),
        BestEffort(
          distanceMeters: 10000,
          duration: Duration(minutes: 57, seconds: 25),
        ),
      ],
    );

    testWidgets('shows the fastest stretch, not the run it came out of', (
      tester,
    ) async {
      await pump(tester, log: <RunSummary>[tenK], now: monday);

      expect(find.text('57:25'), findsOneWidget);
      // The run's own time is on the page — it is in the log row — but it must
      // not be standing in the 10K slot.
      expect(find.text('27:41'), findsOneWidget);
    });

    testWidgets('a distance never run shows the row and no figure', (
      tester,
    ) async {
      await pump(tester, log: <RunSummary>[tenK], now: monday);

      expect(find.text('HALF MARATHON'), findsOneWidget);
      expect(find.text('MARATHON'), findsOneWidget);
      // Two dashes, one per unrun distance, and no invented time beside either.
      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('the best of several runs at one distance is the one shown', (
      tester,
    ) async {
      final slower = RunSummary(
        startedAt: DateTime(2026, 8, 10, 8),
        duration: const Duration(minutes: 30),
        distanceMeters: 5400,
        bestEfforts: const <BestEffort>[
          BestEffort(
            distanceMeters: 5000,
            duration: Duration(minutes: 28, seconds: 3),
          ),
        ],
      );

      await pump(tester, log: <RunSummary>[tenK, slower], now: monday);

      expect(find.text('27:41'), findsOneWidget);
      expect(find.text('28:03'), findsNothing);
    });

    testWidgets('a hand-logged race sets no record, and the page says why', (
      tester,
    ) async {
      // The confusing case, and the one worth spending a line of prose on: a
      // runner who types their marathon in has a marathon in their log and a
      // dash beside "Marathon", because there is no route to read it off.
      final byHand = RunSummary(
        startedAt: DateTime(2026, 5, 4, 9),
        duration: const Duration(hours: 3, minutes: 48),
        distanceMeters: 42195,
      );

      await pump(
        tester,
        log: <RunSummary>[byHand],
        now: DateTime(2026, 5, 5, 9),
      );

      // Four dashes: every record, including the marathon they just ran. The
      // run's own 3:48:00 is on the page in the log row below, and nowhere near
      // the marathon slot.
      expect(find.text('—'), findsNWidgets(4));
      expect(find.textContaining('without a route sets none'), findsOneWidget);
    });

    testWidgets('with nothing unexplained the explanation stays away', (
      tester,
    ) async {
      await pump(tester, log: <RunSummary>[tenK], now: monday);

      expect(find.textContaining('without a route sets none'), findsNothing);
    });

    testWidgets('a short run explains nothing, because it explains itself', (
      tester,
    ) async {
      // Under 5 km, so it was never going to hold a record. Its silence needs
      // no note — only a run long enough to have set one and still setting
      // none is worth a sentence.
      final short = RunSummary(
        startedAt: DateTime(2026, 8, 19, 7),
        duration: const Duration(minutes: 18),
        distanceMeters: 3400,
      );

      await pump(tester, log: <RunSummary>[short]);

      expect(find.textContaining('without a route sets none'), findsNothing);
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
