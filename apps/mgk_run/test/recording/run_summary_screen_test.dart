import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
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

void main() {
  final withData = RunSummary(
    startedAt: DateTime(2026, 7, 21, 7, 32),
    duration: const Duration(minutes: 27, seconds: 45),
    distanceMeters: 5230,
    elevationGainMeters: 42,
    avgHr: 148,
    caloriesEst: 358,
    splits: const <RunSplit>[
      RunSplit(
        index: 1,
        distanceMeters: 1000,
        duration: Duration(seconds: 322),
      ),
      RunSplit(
        index: 2,
        distanceMeters: 1000,
        duration: Duration(seconds: 305),
      ),
    ],
  );

  testWidgets('renders distance, stats, and splits', (tester) async {
    _useTallPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RunSummaryScreen(summary: withData),
      ),
    );

    expect(find.text('5.23 km'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('AVG HR'), findsOneWidget);
    expect(find.text('CALORIES (EST)'), findsOneWidget);
    expect(find.text('SPLITS'), findsOneWidget);
    // No "Done" without an [onDone]: this summary was opened from the log and
    // is dismissed with back, so the button had nothing to do and rendered
    // permanently disabled.
    expect(find.widgetWithText(FilledButton, 'Done'), findsNothing);
  });

  testWidgets('shows Done only when there is somewhere for it to go', (
    tester,
  ) async {
    _useTallPhone(tester);
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RunSummaryScreen(summary: withData, onDone: () => done++),
      ),
    );

    final button = find.widgetWithText(FilledButton, 'Done');
    expect(button, findsOneWidget);
    expect(
      tester.widget<FilledButton>(button).onPressed,
      isNotNull,
      reason: 'a shown Done must be live, never greyed out',
    );

    await tester.tap(button);
    await tester.pump();
    expect(done, 1);
  });

  testWidgets('omits stats and splits that are absent (manual entry)', (
    tester,
  ) async {
    _useTallPhone(tester);
    final manual = RunSummary(
      startedAt: DateTime(2026, 7, 20, 18),
      duration: const Duration(minutes: 50),
      distanceMeters: 10000,
      type: 'manual',
    );

    await tester.pumpWidget(
      MaterialApp(home: RunSummaryScreen(summary: manual)),
    );

    // No HR, no calories, no splits section — designed for absence.
    expect(find.text('AVG HR'), findsNothing);
    expect(find.text('SPLITS'), findsNothing);
    expect(find.textContaining('Manual entry'), findsOneWidget);
  });
}
