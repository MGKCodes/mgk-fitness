import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_screen.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_note.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/training_history.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/week_progress.dart';
import 'package:mgk_run/src/features/home/presentation/home_tab.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/profile/presentation/profile_screen.dart';
import 'package:mgk_run/src/features/profile/presentation/year_grid.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:flutter/material.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_split.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/recording/presentation/run_summary_screen.dart';

import 'plate.dart';

/// **The whole app, one screen per plate, on a surface a runner actually
/// holds.**
///
/// The sibling board (`board.dart`) does this for every *state of one screen*.
/// This does it for every *screen*, which answers the other half of the same
/// question: a screen that looks fine on its own often looks like a different
/// app beside its neighbours, and nothing in a test suite ever notices that.
/// Type scale drifts, a card's corner radius stops matching the one on the tab
/// before it, two surfaces disagree about what grey a label is. Every one of
/// those passes 1,186 tests.
///
/// Regenerate the lot with:
///
///     flutter test test/plates/screens.dart
///
/// **Both states of a pair are here on purpose.** Home with a plan and Home
/// without it are the pair that matters most — ADR-0019 bets the free product
/// is a coherent app rather than the paid one with its contents removed, and
/// the only way to judge that bet is to look at the two of them side by side.
/// The same goes for a profile with a log and a profile without one.
///
/// Rendered at [kPhone] and **not scrolled**: this is the fold, which is the
/// thing worth judging. A page that has to be scrolled before it says anything
/// is exactly what this board should make obvious rather than hide.
///
/// Basemap tiles are absent — the test framework answers every network image
/// with a 400 — so the map's ground, route and marker are real and only the
/// tile art is missing.
void main() {
  /// A Monday afternoon in August. Everything here pins the clock, because
  /// three surfaces read the hour and a board where they disagree is a board
  /// that cannot be trusted.
  final monday = DateTime(2026, 8, 24, 15);

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

  /// A loop around South Park, Reigate — roughly the 23 Aug test run.
  ///
  /// **A plate is only as honest as what it is fed.** The first version of this
  /// file built the finished run out of three required fields, so the screen
  /// drew no route, no splits, no steps and no elevation — and the board
  /// reported that as the screen being empty rather than as the fixture being
  /// thin. `plate.dart` already says a plate drawn at a size no runner holds is
  /// worse than no plate because it looks like evidence; data is the same
  /// argument, and this is the shape it takes.
  List<RunPoint> loop() {
    const lat = 51.2300, lng = -0.2050;
    return <RunPoint>[
      for (var i = 0; i <= 120; i++)
        RunPoint(
          // A closed, slightly lopsided loop rather than a circle — a real
          // route doubles back, and a marker cluster on a doubled-back leg is
          // exactly what this plate exists to let somebody judge.
          latitude: lat + 0.011 * math.sin(i / 120 * 2 * math.pi),
          longitude:
              lng +
              0.017 * math.cos(i / 120 * 2 * math.pi) +
              0.003 * math.sin(i / 120 * 6 * math.pi),
          accuracyMeters: 6,
          timestamp: DateTime(
            2026,
            8,
            23,
            14,
            2,
          ).add(Duration(seconds: i * 29)),
        ),
    ];
  }

  /// The splits the 23 Aug run actually turned over, from `IMG_4685`.
  const splitSeconds = <int>[307, 311, 323, 367, 291, 359, 325, 437, 380, 339];

  final finished = RunSummary(
    id: 'plate-run',
    startedAt: DateTime(2026, 8, 23, 14, 2),
    duration: const Duration(minutes: 58, seconds: 28),
    distanceMeters: 10180,
    avgPaceSecondsPerKm: 345,
    // Both present here on purpose, and both routinely absent in the field:
    // elevation needs a barometer the app does not yet have (ADR-0024) and
    // steps need a granted Health read. The plate shows the screen with its
    // data so the layout can be judged; the absence is judged on the sibling.
    elevationGainMeters: 167,
    elevationMaxMeters: 111,
    steps: 8468,
    points: loop(),
    splits: <RunSplit>[
      for (var i = 0; i < splitSeconds.length; i++)
        RunSplit(
          index: i + 1,
          distanceMeters: 1000,
          duration: Duration(seconds: splitSeconds[i]),
        ),
      const RunSplit(
        index: 11,
        distanceMeters: 180,
        duration: Duration(seconds: 57),
      ),
    ],
  );

  /// A year of running, thinning out in winter and building through summer —
  /// the shape the year grid exists to show, and one a flat fixture cannot.
  final year = <RunSummary>[
    for (var d = 0; d < 360; d++)
      if (<int>[1, 3, 5, 7][d % 4] != 7 || d % 7 == 6)
        if ((d ~/ 30) % 5 != 0 || d % 3 == 0)
          run(
            at: DateTime(2026, 8, 24).subtract(Duration(days: d)),
            meters: 4200 + (d % 30) * 520.0 + (d % 7 == 6 ? 9000 : 0),
            duration: Duration(minutes: 26 + (d % 30)),
          ),
  ];

  final log = <RunSummary>[
    run(
      at: DateTime(2026, 8, 22),
      meters: 21100,
      duration: const Duration(hours: 1, minutes: 58),
    ),
    run(at: DateTime(2026, 8, 20)),
    run(
      at: DateTime(2026, 8, 17),
      meters: 10180,
      duration: const Duration(minutes: 58, seconds: 28),
    ),
    run(
      at: DateTime(2026, 8, 15),
      meters: 5200,
      duration: const Duration(minutes: 27, seconds: 4),
    ),
  ];

  List<List<RunDay>> gridWith(List<RunDay> thisWeek) => <List<RunDay>>[
    for (var w = 0; w < 7; w++) List<RunDay>.filled(7, RunDay.none),
    thisWeek,
  ];

  final thisWeekRan = gridWith(<RunDay>[
    RunDay.none,
    RunDay.none,
    RunDay.none,
    RunDay.none,
    RunDay.ran,
    RunDay.none,
    RunDay.none,
  ]);

  // --- Home ------------------------------------------------------------------

  testWidgets('home — with a plan', (tester) async {
    await plate(
      tester,
      'home-with-plan',
      HomeTab(
        onRecord: () {},
        onOpenPlan: () {},
        now: monday,
        today: planned,
        thisWeek: week,
        outcomes: const <int, DayOutcome>{DateTime.friday: DayOutcome.upcoming},
        standing: const WeekStanding(
          ranMeters: 14200,
          plannedMeters: 15149,
          done: 0,
          sessions: 2,
        ),
        stats: RunnerStats.from(log, now: monday),
        lastRun: log.first,
        hasRuns: true,
        consistency: thisWeekRan,
        note: const CoachNote(
          headline: 'Two easy weeks in a row is the build working.',
          detail:
              '31 km last week against 29 the week before, both inside the '
              'band the plan asked for.',
        ),
      ),
      pixelRatio: 2,
    );
  });

  testWidgets('home — no plan, which is the free product', (tester) async {
    await plate(
      tester,
      'home-no-plan',
      HomeTab(
        onRecord: () {},
        onOpenPlan: () {},
        now: monday,
        stats: RunnerStats.from(log, now: monday),
        lastRun: log.first,
        hasRuns: true,
        consistency: thisWeekRan,
      ),
      pixelRatio: 2,
    );
  });

  testWidgets('home — nothing recorded yet', (tester) async {
    await plate(
      tester,
      'home-first-launch',
      HomeTab(
        onRecord: () {},
        onOpenPlan: () {},
        now: monday,
        stats: RunnerStats.from(const <RunSummary>[], now: monday),
        hasRuns: false,
        consistency: gridWith(List<RunDay>.filled(7, RunDay.none)),
      ),
      pixelRatio: 2,
    );
  });

  // --- Profile ---------------------------------------------------------------

  testWidgets('profile — with a log', (tester) async {
    await plate(
      tester,
      'profile-with-log',
      ProfileScreen(
        stats: RunnerStats.from(year, now: monday),
        runs: year,
        now: monday,
        onAddRun: () {},
        onOpenSettings: () {},
      ),
      pixelRatio: 2,
    );
  });

  testWidgets('profile — before the first run', (tester) async {
    await plate(
      tester,
      'profile-empty',
      ProfileScreen(
        stats: RunnerStats.from(const <RunSummary>[], now: monday),
        now: monday,
        onAddRun: () {},
        onOpenSettings: () {},
      ),
      pixelRatio: 2,
    );
  });

  // --- After the finish line -------------------------------------------------

  testWidgets('run complete — the screen that did not exist', (tester) async {
    await plate(
      tester,
      'run-complete',
      RunSummaryScreen(
        summary: finished,
        history: log,
        justFinished: true,
        onDone: () {},
        onAskCoach: () {},
      ),
      pixelRatio: 2,
    );
  });

  testWidgets('run summary — the same run, opened from the log', (
    tester,
  ) async {
    await plate(
      tester,
      'run-from-log',
      RunSummaryScreen(
        summary: finished,
        history: log,
        onEdit: () {},
        onAskCoach: () {},
      ),
      pixelRatio: 2,
    );
  });

  // --- The plan ---------------------------------------------------------------

  testWidgets('plan — the week, and the block behind it', (tester) async {
    final planNow = DateTime(2026, 7, 25);
    final profile = RunnerProfile(
      goalDistanceMeters: 42195,
      eventDate: DateTime(2026, 11, 1),
      currentWeeklyMeters: 40000,
      longestRecentMeters: 18000,
      daysPerWeek: 5,
      availableWeekdays: const <int>{1, 2, 4, 6, 7},
      timeTrialDistanceMeters: 5000,
      timeTrialDuration: const Duration(minutes: 22),
    );
    final skeleton = buildSkeleton(profile, now: planNow);
    final stored = StoredPlan(
      id: 'plate-plan',
      profile: profile,
      skeleton: skeleton,
      startDate: mondayOf(planNow),
    );
    await plate(
      tester,
      'plan-week',
      PlanScreen(
        plan: stored,
        weeks: <int, TrainingWeek>{
          1: buildFallbackWeek(skeleton.weeks[0], profile),
          2: buildFallbackWeek(skeleton.weeks[1], profile),
        },
        now: planNow,
        statusFor: (_) => SessionStatus.planned,
        onOpenWeek: (_, _) {},
        onOpenCalendar: () {},
        onOpenBlock: () {},
      ),
      pixelRatio: 2,
    );
  });

  testWidgets('the year grid, on its own', (tester) async {
    await plate(
      tester,
      'year-grid',
      Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: YearGrid(weeks: runYear(runs: year, now: monday)),
          ),
        ),
      ),
      size: const Size(393, 340),
      pixelRatio: 3,
    );
  });

  testWidgets('the year grid, before the first run', (tester) async {
    await plate(
      tester,
      'year-grid-empty',
      Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: YearGrid(
              weeks: runYear(runs: const <RunSummary>[], now: monday),
            ),
          ),
        ),
      ),
      size: const Size(393, 340),
      pixelRatio: 3,
    );
  });
}
