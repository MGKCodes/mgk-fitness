import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_history.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/profile/presentation/profile_screen.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// Every plan Runio ever built was already on disk. Nothing showed them, so a
/// runner three blocks in saw the same Profile tab as one who arrived today.
void main() {
  RunSummary run(DateTime at, double meters) => RunSummary(
    startedAt: at,
    duration: const Duration(minutes: 30),
    distanceMeters: meters,
  );

  final runs = <RunSummary>[run(DateTime(2026, 7, 28), 8000)];

  PlanRecord record({
    required String id,
    required DateTime start,
    DateTime? event,
    DateTime? endedAt,
    double? goal = 42195,
    int weeks = 16,
    bool active = false,
  }) => PlanRecord(
    id: id,
    startDate: start,
    weeks: weeks,
    isActive: active,
    goalDistanceMeters: goal,
    eventDate: event,
    endedAt: endedAt,
  );

  Future<void> pump(WidgetTester tester, List<PlanRecord> history) async {
    // Past ones only, the way the shell filters them.
    final labelled = labelPlans(
      history,
    ).where((p) => !p.record.isActive).toList();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ProfileScreen(
          stats: RunnerStats.from(runs),
          runs: runs,
          pastPlans: labelled,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a finished block is listed with its label', (tester) async {
    await pump(tester, <PlanRecord>[
      record(
        id: 'a',
        start: DateTime(2025, 1, 6),
        event: DateTime(2025, 4, 20),
        endedAt: DateTime(2025, 5, 1),
      ),
      record(id: 'b', start: DateTime(2026, 7, 27), active: true),
    ]);

    expect(find.text('BEFORE THIS'), findsOneWidget);
    // Numbered 1, not unnumbered: the plan they are on now is also a marathon,
    // so there are two to tell apart even though only one is in the past. The
    // numbering counts every plan of that kind, which is what keeps the label
    // stable — this one stays "Marathon plan 1" for good.
    expect(find.text('Marathon plan 1'), findsOneWidget);
    // Finished, so no week number — "week 16 of 16" is a strange way to say it.
    expect(find.textContaining('Jan 2025 · 16 weeks'), findsOneWidget);
    expect(find.textContaining('stopped at'), findsNothing);
  });

  testWidgets('one they stopped short says where they got to', (tester) async {
    await pump(tester, <PlanRecord>[
      record(
        id: 'a',
        start: DateTime(2025, 1, 6),
        event: DateTime(2025, 4, 20),
        endedAt: DateTime(2025, 3, 5),
      ),
      record(id: 'b', start: DateTime(2026, 7, 27), active: true),
    ]);

    expect(find.textContaining('stopped at week 9 of 16'), findsOneWidget);
  });

  testWidgets('the current plan is not in the history', (tester) async {
    // It is the whole Coach tab. Listing it here would read as two plans.
    await pump(tester, <PlanRecord>[
      record(id: 'b', start: DateTime(2026, 7, 27), active: true),
    ]);

    expect(find.text('BEFORE THIS'), findsNothing);
  });

  testWidgets('a first-time runner gets no empty section', (tester) async {
    await pump(tester, const <PlanRecord>[]);
    expect(find.text('BEFORE THIS'), findsNothing);
  });

  testWidgets('newest first on screen, oldest first in the numbering', (
    tester,
  ) async {
    // Two different orderings for two different jobs: labels count up from the
    // first plan so they stay put, and a runner scanning their past reads the
    // most recent thing first.
    await pump(tester, <PlanRecord>[
      record(id: 'a', start: DateTime(2024, 1, 1)),
      record(id: 'b', start: DateTime(2025, 1, 6)),
      record(id: 'c', start: DateTime(2026, 7, 27), active: true),
    ]);

    final first = tester.getTopLeft(find.text('Marathon plan 2'));
    final second = tester.getTopLeft(find.text('Marathon plan 1'));
    expect(
      first.dy,
      lessThan(second.dy),
      reason: 'the more recent plan is higher up the page',
    );
  });

  testWidgets('a rhythm is named rather than measured', (tester) async {
    await pump(tester, <PlanRecord>[
      record(id: 'a', start: DateTime(2025, 1, 6), goal: null, weeks: 12),
      record(id: 'b', start: DateTime(2026, 7, 27), active: true),
    ]);

    expect(find.text('Keeping a rhythm'), findsOneWidget);
  });
}
