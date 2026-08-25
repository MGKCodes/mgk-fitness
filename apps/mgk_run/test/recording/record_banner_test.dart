import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/recording/domain/best_effort.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/recording/presentation/run_summary_screen.dart';

/// **Telling a runner they set a record, on the screen where they set it.**
///
/// Everything needed was already here — the run carries its own best efforts
/// and the log is passed in to compare them against — so the absence was not a
/// missing feature so much as a missing sentence. Without it somebody could set
/// their fastest 10K and find out by opening a different tab.
///
/// What the tests below mostly guard is the *other* direction: a banner that
/// fires when it should not is worse than no banner, because it devalues the
/// one time it matters.
void main() {
  RunSummary run({
    String? id,
    Duration best = const Duration(minutes: 45),
    double meters = 10500,
  }) => RunSummary(
    id: id,
    startedAt: DateTime(2026, 8, 24, 7),
    duration: const Duration(minutes: 55),
    distanceMeters: meters,
    bestEfforts: <BestEffort>[
      BestEffort(distanceMeters: 10000, duration: best),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    RunSummary summary,
    List<RunSummary> history,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RunSummaryScreen(
          summary: summary,
          history: history,
          justFinished: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a first 10K is a record, because there is nothing to beat', (
    tester,
  ) async {
    await pump(tester, run(), const <RunSummary>[]);

    expect(find.text('Fastest 10K yet'), findsOneWidget);
  });

  testWidgets('a slower run than before says nothing', (tester) async {
    await pump(tester, run(best: const Duration(minutes: 48)), <RunSummary>[
      run(id: 'older', best: const Duration(minutes: 44)),
    ]);

    expect(find.textContaining('Fastest'), findsNothing);
  });

  testWidgets('matching a time already held is not a new record', (
    tester,
  ) async {
    // Strictly faster, never a tie. Telling somebody a repeat is a record is
    // the cheapest way to make the banner mean nothing.
    await pump(tester, run(best: const Duration(minutes: 45)), <RunSummary>[
      run(id: 'older', best: const Duration(minutes: 45)),
    ]);

    expect(find.textContaining('Fastest'), findsNothing);
  });

  testWidgets('a run cannot beat itself', (tester) async {
    // The log handed to this screen usually already contains the run being
    // shown — Home refreshes before it opens the summary — so without skipping
    // by id, every record would immediately fail to be one.
    final it = run(id: 'this-run');
    await pump(tester, it, <RunSummary>[it]);

    expect(find.text('Fastest 10K yet'), findsOneWidget);
  });

  testWidgets('several set at once are named in one line', (tester) async {
    // 5K, 10K and half all fall inside a marathon. Three banners would bury the
    // run under its own confetti.
    final marathon = RunSummary(
      startedAt: DateTime(2026, 8, 24, 7),
      duration: const Duration(hours: 3, minutes: 40),
      distanceMeters: 42400,
      bestEfforts: const <BestEffort>[
        BestEffort(distanceMeters: 5000, duration: Duration(minutes: 24)),
        BestEffort(distanceMeters: 10000, duration: Duration(minutes: 50)),
      ],
    );
    await pump(tester, marathon, const <RunSummary>[]);

    expect(find.text('Fastest 5K and 10K yet'), findsOneWidget);
  });

  testWidgets('a run with no trace has no efforts and says nothing', (
    tester,
  ) async {
    final typed = RunSummary(
      startedAt: DateTime(2026, 8, 24, 7),
      duration: const Duration(minutes: 50),
      distanceMeters: 10000,
    );
    await pump(tester, typed, const <RunSummary>[]);

    expect(find.textContaining('Fastest'), findsNothing);
  });
}
