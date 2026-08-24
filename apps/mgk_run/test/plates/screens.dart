import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_note.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/training_history.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/week_progress.dart';
import 'package:mgk_run/src/features/home/presentation/home_tab.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/profile/presentation/profile_screen.dart';
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
        stats: RunnerStats.from(log, now: monday),
        runs: log,
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
        summary: run(
          at: DateTime(2026, 8, 23, 14, 2),
          meters: 10180,
          duration: const Duration(minutes: 58, seconds: 28),
        ),
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
        summary: run(
          at: DateTime(2026, 8, 23, 14, 2),
          meters: 10180,
          duration: const Duration(minutes: 58, seconds: 28),
        ),
        history: log,
        onEdit: () {},
        onAskCoach: () {},
      ),
      pixelRatio: 2,
    );
  });
}
