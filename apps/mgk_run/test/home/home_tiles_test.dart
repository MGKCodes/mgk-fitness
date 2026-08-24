import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_note.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/training_history.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/week_progress.dart';
import 'package:mgk_run/src/features/home/presentation/home_tab.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// Home as a grid of tiles, and the rule that decides which tiles exist.
///
/// **A tile earns its place by being true for every runner every day.** Today
/// is always a day, the week is always a week, and every runner has a log even
/// when it is empty. So the three assertions that matter here are that the
/// same tiles appear with a plan and without one, that they carry *different
/// facts* rather than the same facts emptied out, and that a runner who has
/// recorded nothing gets the page held open at dashes rather than collapsed.
///
/// The second of those is the one worth spelling out. A free Home that is a
/// paid Home with the contents removed — an empty week ribbon, a "no plan yet"
/// card where a session would be — is the counter-signal
/// [ADR-0019](../../../lib/../docs/decisions/0019-onboarding-is-two-moments.md)
/// names for its own reversal, and it is what this screen used to be.
void main() {
  /// A Monday afternoon, so "Afternoon" is the time of day and Monday is the
  /// weekday, whatever day the suite actually runs on. Everything in this file
  /// pins the clock: a page that reads the hour in three places has to be
  /// testable at one hour.
  final mondayAfternoon = DateTime(2026, 8, 24, 15);

  const threshold = PlannedSession(
    weekday: DateTime.monday,
    kind: SessionKind.threshold,
    distanceMeters: 8900,
  );
  const friday = PlannedSession(
    weekday: DateTime.friday,
    kind: SessionKind.easy,
    distanceMeters: 6249,
  );
  const week = TrainingWeek(
    skeletonIndex: 3,
    sessions: <PlannedSession>[threshold, friday],
  );
  const slot = SkeletonWeek(
    index: 3,
    phase: Phase.build,
    volumeMeters: 31766,
    longRunMeters: 12480,
  );
  const planned = TodayView(
    slot: slot,
    session: threshold,
    status: SessionStatus.planned,
    heading: 'Today',
  );

  RunSummary run({
    required DateTime at,
    double meters = 8400,
    Duration duration = const Duration(minutes: 48, seconds: 12),
  }) => RunSummary(startedAt: at, duration: duration, distanceMeters: meters);

  /// The current week off the log, in the shape `consistencyGrid` hands Home:
  /// eight rows, the last of which is this week.
  List<List<RunDay>> gridWith(List<RunDay> thisWeek) => <List<RunDay>>[
    for (var w = 0; w < 7; w++) List<RunDay>.filled(7, RunDay.none),
    thisWeek,
  ];

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(430, 2400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: home));
    await tester.pumpAndSettle();
  }

  group('with a plan', () {
    Widget planned_() => HomeTab(
      onRecord: () {},
      onOpenPlan: () {},
      now: mondayAfternoon,
      today: planned,
      thisWeek: week,
      outcomes: const <int, DayOutcome>{DateTime.friday: DayOutcome.upcoming},
      standing: const WeekStanding(
        ranMeters: 14200,
        plannedMeters: 15149,
        done: 0,
        sessions: 2,
      ),
      stats: RunnerStats.from(<RunSummary>[
        run(at: DateTime(2026, 8, 22), meters: 21100),
        run(at: DateTime(2026, 8, 20)),
      ], now: mondayAfternoon),
      lastRun: run(at: DateTime(2026, 8, 22), meters: 21100),
      hasRuns: true,
      consistency: gridWith(<RunDay>[
        RunDay.none,
        RunDay.none,
        RunDay.none,
        RunDay.none,
        RunDay.ran,
        RunDay.none,
        RunDay.none,
      ]),
    );

    testWidgets('today names the session as an activity, with the hour on it', (
      tester,
    ) async {
      await pump(tester, planned_());

      // "Afternoon threshold run", not "Threshold". The old card read TODAY
      // over Threshold — two headings, no sentence, and a physiological zone
      // where a runner wants the name of a thing they are about to go and do.
      expect(find.text('Afternoon threshold run'), findsOneWidget);
      expect(find.text('Threshold'), findsNothing);

      // And the eyebrow is a date, which cannot be mistaken for a second
      // heading. `SectionLabel` upper-cases what it is given.
      expect(find.text('TODAY · MONDAY 24 AUG'), findsOneWidget);
    });

    testWidgets(
      'and the button says what is about to start, without the hour',
      (tester) async {
        await pump(tester, planned_());

        // The headline names the occasion; the button names the thing. "Start ·
        // 9 km afternoon threshold run" is nobody's sentence.
        expect(find.text('Start · 9 km threshold run'), findsOneWidget);
      },
    );

    testWidgets('the week tile counts sessions and looks forward', (
      tester,
    ) async {
      await pump(tester, planned_());

      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('0 of 2'), findsOneWidget);
      expect(find.text('14.2 km'), findsOneWidget);

      // A session four days out has no hour attached to it, so it does not get
      // one — the distinction `sessionNameAt` and `sessionName` exist for.
      expect(
        find.textContaining('Next · easy run 6 km on Friday'),
        findsOneWidget,
      );
      expect(find.textContaining('afternoon easy run'), findsNothing);
    });

    testWidgets('and the runner’s own record is on the page too', (
      tester,
    ) async {
      await pump(tester, planned_());

      expect(find.text('YOUR RUNNING'), findsOneWidget);
      expect(find.text('LAST RUN'), findsOneWidget);
      expect(find.text('LONGEST RUN'), findsOneWidget);
      expect(find.text('FASTEST PACE'), findsOneWidget);
      expect(find.text('RUNS LOGGED'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('without a plan', () {
    /// [weekMeters] and [ranDays] are this week alone; [runs] is the whole log,
    /// which is deliberately longer. The two figures on the week tile and the
    /// two on the grid below it come from different windows, and a fixture
    /// where they happened to match would hide a tile reading the wrong one.
    Widget free({
      List<RunSummary> runs = const <RunSummary>[],
      double weekMeters = 0,
      List<RunDay> ranDays = const <RunDay>[],
    }) => HomeTab(
      onRecord: () {},
      onOpenPlan: () {},
      now: mondayAfternoon,
      stats: RunnerStats.from(runs, now: mondayAfternoon),
      lastRun: runs.isEmpty ? null : runs.first,
      hasRuns: runs.isNotEmpty,
      standing: WeekStanding(
        ranMeters: weekMeters,
        plannedMeters: 0,
        done: 0,
        sessions: 0,
      ),
      consistency: gridWith(
        ranDays.isEmpty ? List<RunDay>.filled(7, RunDay.none) : ranDays,
      ),
    );

    /// One run this week and one the week before, so the week tile's count and
    /// the lifetime count are different numbers.
    Widget freeWithHistory() => free(
      runs: <RunSummary>[
        run(at: DateTime(2026, 8, 24, 7), meters: 8400),
        run(at: DateTime(2026, 8, 19), meters: 5000),
      ],
      weekMeters: 8400,
      ranDays: <RunDay>[
        RunDay.ran,
        RunDay.none,
        RunDay.none,
        RunDay.none,
        RunDay.none,
        RunDay.none,
        RunDay.none,
      ],
    );

    testWidgets('there is no plan-shaped hole anywhere on the page', (
      tester,
    ) async {
      await pump(
        tester,
        free(runs: <RunSummary>[run(at: DateTime(2026, 8, 22))], weekMeters: 0),
      );

      // The exact counter-signal ADR-0019 watches for: a card headed with the
      // name of the thing the runner has not bought.
      expect(find.text('No plan yet'), findsNothing);
      expect(find.textContaining('plan'), findsNothing);
    });

    testWidgets('and the same tiles are there, answering off the log', (
      tester,
    ) async {
      await pump(tester, freeWithHistory());

      // Today, the week, the record, the coach — the four permanent tiles, all
      // of them present without a plan behind any of them.
      //
      // "Morning run" for a run started at seven, on a page whose clock says
      // three in the afternoon: the occasion comes off the run rather than off
      // the hour the runner happens to be reading this at.
      expect(find.text('Morning run'), findsOneWidget);
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('YOUR RUNNING'), findsOneWidget);
      expect(find.text('FROM YOUR COACH'), findsOneWidget);

      // The week tile counts *runs*, because there are no sessions to count.
      expect(find.text('RUNS'), findsOneWidget);
      expect(find.text('SESSIONS'), findsNothing);
      expect(find.text('1'), findsOneWidget); // one run this week
      expect(find.text('2'), findsOneWidget); // two in the log
      expect(find.text('8.4 km'), findsWidgets);
    });

    testWidgets('a run recorded today is what today says', (tester) async {
      await pump(
        tester,
        free(
          runs: <RunSummary>[run(at: DateTime(2026, 8, 24, 12, 30))],
          weekMeters: 8400,
        ),
      );

      // "Afternoon run" — the same vocabulary a planned session gets, off the
      // run's own start rather than off the clock.
      expect(find.text('Afternoon run'), findsOneWidget);
      expect(find.text('No run yet today'), findsNothing);
      // A distance the runner covered keeps its decimal: prescriptions round,
      // achievements do not.
      expect(find.text('8.4 km'), findsWidgets);
      expect(find.text('48:12  ·  5:44 /km'), findsOneWidget);
      expect(find.text('Record another run'), findsOneWidget);
    });
  });

  group('with no runs at all', () {
    Widget blank() => HomeTab(
      onRecord: () {},
      onOpenPlan: () {},
      now: mondayAfternoon,
      standing: const WeekStanding(
        ranMeters: 0,
        plannedMeters: 0,
        done: 0,
        sessions: 0,
      ),
      consistency: gridWith(List<RunDay>.filled(7, RunDay.none)),
    );

    testWidgets('the page states its structure rather than its emptiness', (
      tester,
    ) async {
      await pump(tester, blank());

      // Every tile is here, held open. A screen with no data states its
      // structure — the general rule ADR-0019 leaves behind, arrived at on the
      // Profile tab and applied here.
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('YOUR RUNNING'), findsOneWidget);
      expect(find.text('FROM YOUR COACH'), findsOneWidget);

      // A dash is an absence where a zero would be a claim. Four stat tiles
      // plus both figures on the week tile.
      expect(find.text('—'), findsNWidgets(6));
      expect(find.textContaining('0.0 km'), findsNothing);

      // And each dash is captioned with what will land on it.
      expect(find.text('Your latest run lands here'), findsOneWidget);
      expect(find.text('Every run you record'), findsOneWidget);
    });

    testWidgets('the coach keeps its place before it has anything to say', (
      tester,
    ) async {
      await pump(tester, blank());

      // The tile used to be dropped whenever `CoachNote.forRuns` had nothing
      // honest to say — which is exactly the state a new runner is in, so the
      // one surface saying anybody is paying attention was missing from the
      // screen somebody decides on.
      expect(find.text('Nothing to go on yet.'), findsOneWidget);
      expect(
        find.textContaining('Record a run and your coach'),
        findsOneWidget,
      );
    });

    testWidgets('and the free product is still described', (tester) async {
      await pump(tester, blank());
      expect(find.text('ONCE YOU RUN'), findsOneWidget);
      expect(find.textContaining('route, pace and splits'), findsOneWidget);
    });

    testWidgets('a note is never invented from a log with nothing in it', (
      tester,
    ) async {
      // Belt and braces on the tile's own copy: whatever the coach is given,
      // an empty log produces nothing for it to say.
      expect(CoachNote.forRuns(const <RunSummary>[]), isNull);
      await pump(tester, blank());
      expect(find.text('Nothing new to flag.'), findsNothing);
    });
  });

  group('runs, but nothing worth a remark', () {
    testWidgets('the coach says so rather than praising them for it', (
      tester,
    ) async {
      await pump(
        tester,
        HomeTab(
          onRecord: () {},
          onOpenPlan: () {},
          now: mondayAfternoon,
          hasRuns: true,
          stats: RunnerStats.from(<RunSummary>[
            run(at: DateTime(2026, 8, 22)),
          ], now: mondayAfternoon),
          lastRun: run(at: DateTime(2026, 8, 22)),
          standing: const WeekStanding(
            ranMeters: 8400,
            plannedMeters: 0,
            done: 0,
            sessions: 0,
          ),
          consistency: gridWith(List<RunDay>.filled(7, RunDay.none)),
        ),
      );

      // "Steady work" would be a claim about training this tile has not
      // checked, and a second voice for a fact the charts below already draw
      // (ADR-0017).
      expect(find.text('Nothing new to flag.'), findsOneWidget);
      expect(find.text('Nothing to go on yet.'), findsNothing);
    });
  });

  group('one clock for the whole page', () {
    testWidgets('the header and today cannot disagree at six o’clock', (
      tester,
    ) async {
      // Home's header carried its own `_greeting()` — the same three words and
      // the same two boundaries as `timeOfDayName`, kept in step by hand. Two
      // answers to "what time of day is it" in one app is a bug waiting for
      // the evening boundary, and this is the screen it would have shown up on.
      await pump(
        tester,
        HomeTab(
          onRecord: () {},
          onOpenPlan: () {},
          now: DateTime(2026, 8, 24, 18, 5),
          today: planned,
          thisWeek: week,
          consistency: gridWith(List<RunDay>.filled(7, RunDay.none)),
        ),
      );

      expect(find.text('Evening threshold run'), findsOneWidget);
      expect(find.text('Afternoon threshold run'), findsNothing);
    });

    testWidgets('and with no plan the greeting is the header', (tester) async {
      await pump(
        tester,
        HomeTab(
          onRecord: () {},
          onOpenPlan: () {},
          now: DateTime(2026, 8, 24, 18, 5),
          consistency: gridWith(List<RunDay>.filled(7, RunDay.none)),
        ),
      );

      expect(find.text('Evening'), findsOneWidget);
    });
  });

  group('it fits a phone', () {
    testWidgets('the whole page scrolls without a single overflow', (
      tester,
    ) async {
      // The tiles are squares in a two-column grid and the figures inside them
      // are unbounded — an imperial pace is wider than a metric one, and a
      // `Text` in a bounded box clips silently. Scrolling the lot at a real
      // phone width is the only way to see a break.
      await pump(
        tester,
        HomeTab(
          onRecord: () {},
          onOpenPlan: () {},
          now: mondayAfternoon,
          unit: UnitSystem.imperial,
          today: planned,
          thisWeek: week,
          hasRuns: true,
          stats: RunnerStats.from(<RunSummary>[
            run(at: DateTime(2026, 8, 22), meters: 42195),
            run(
              at: DateTime(2026, 8, 20),
              duration: const Duration(hours: 4, minutes: 12, seconds: 8),
            ),
          ], now: mondayAfternoon),
          lastRun: run(
            at: DateTime(2026, 8, 22),
            meters: 42195,
            duration: const Duration(hours: 4, minutes: 12, seconds: 8),
          ),
          standing: const WeekStanding(
            ranMeters: 50595,
            plannedMeters: 15149,
            done: 1,
            sessions: 2,
          ),
          consistency: gridWith(List<RunDay>.filled(7, RunDay.ran)),
        ),
        size: const Size(360, 780),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
