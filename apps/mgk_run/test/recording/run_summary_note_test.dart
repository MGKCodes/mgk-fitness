import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/core/units/unit_system.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_button.dart';
import 'package:mgk_run/src/features/recording/domain/run_split.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/recording/presentation/run_summary_screen.dart';

/// Give the screen a tall phone viewport so the whole scroll view lays out
/// (slivers only build what's near the viewport otherwise).
void _useTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester, {
  required RunSummary summary,
  List<RunSummary> history = const <RunSummary>[],
  PlannedSession? planned,
  UnitSystem unit = UnitSystem.metric,
}) async {
  _useTallPhone(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: RunSummaryScreen(
        summary: summary,
        history: history,
        plannedSession: planned,
        unit: unit,
      ),
    ),
  );
}

/// The card's coach mark — the marker that the coach said anything at all.
///
/// It was `Icons.auto_awesome_outlined` until the coach was given one mark
/// instead of two: a C on the floating button and the universal chatbot
/// sparkle on every surface the coach actually spoke from.
final Finder _noteIcon = find.byType(CoachLetter);

void main() {
  final day = DateTime(2026, 7, 26, 8);

  RunSummary run({
    required DateTime at,
    required double meters,
    double? pace,
    List<RunSplit> splits = const <RunSplit>[],
  }) => RunSummary(
    startedAt: at,
    duration: const Duration(minutes: 30),
    distanceMeters: meters,
    avgPaceSecondsPerKm: pace,
    splits: splits,
  );

  List<RunSummary> steady() => <RunSummary>[
    for (var i = 1; i <= 4; i++)
      run(at: day.subtract(Duration(days: i * 3)), meters: 5000, pace: 330),
  ];

  testWidgets('shows the coach’s note about the run', (tester) async {
    await _pump(
      tester,
      summary: run(at: day, meters: 12000, pace: 340),
      history: steady(),
    );

    expect(_noteIcon, findsOneWidget);
    expect(find.text('Furthest you’ve been.'), findsOneWidget);
    expect(find.textContaining('12.00 km'), findsWidgets);
  });

  testWidgets('a run there is nothing true to say about shows nothing', (
    tester,
  ) async {
    await _pump(
      tester,
      summary: run(at: day, meters: 5100, pace: 328),
      history: steady(),
    );

    expect(_noteIcon, findsNothing);
  });

  testWidgets('no history at all is silence, not an empty state', (
    tester,
  ) async {
    await _pump(tester, summary: run(at: day, meters: 5000, pace: 330));

    expect(_noteIcon, findsNothing);
    // The rest of the screen is unaffected.
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('AVG PACE'), findsOneWidget);
  });

  testWidgets('a manual entry with no data to lean on shows no note', (
    tester,
  ) async {
    await _pump(
      tester,
      summary: RunSummary(
        startedAt: day,
        duration: const Duration(minutes: 50),
        distanceMeters: 10000,
        type: 'manual',
      ),
    );

    expect(_noteIcon, findsNothing);
    expect(find.textContaining('Manual entry'), findsOneWidget);
  });

  testWidgets('the note reads the splits when there is no history', (
    tester,
  ) async {
    await _pump(
      tester,
      summary: run(
        at: day,
        meters: 5000,
        pace: 330,
        splits: <RunSplit>[
          for (var i = 0; i < 5; i++)
            RunSplit(
              index: i + 1,
              distanceMeters: 1000,
              duration: Duration(seconds: <int>[345, 340, 330, 320, 315][i]),
            ),
        ],
      ),
    );

    expect(find.text('You finished faster than you started.'), findsOneWidget);
  });

  testWidgets('the note is compared against the session prescribed', (
    tester,
  ) async {
    await _pump(
      tester,
      summary: run(at: day, meters: 8200, pace: 330),
      planned: const PlannedSession(
        weekday: DateTime.sunday,
        kind: SessionKind.easy,
        distanceMeters: 8000,
      ),
    );

    expect(find.text('That’s the session.'), findsOneWidget);
  });

  testWidgets('the note converts at display like the rest of the screen', (
    tester,
  ) async {
    await _pump(
      tester,
      summary: run(at: day, meters: 12000, pace: 340),
      history: steady(),
      unit: UnitSystem.imperial,
    );

    expect(find.textContaining('7.46 mi'), findsWidgets);
  });
}
