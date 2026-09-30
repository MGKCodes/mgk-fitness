import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/recording/data/run_recovery.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_split.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/recording/presentation/route_map.dart';
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

  // Board F7, test sheet C21: a run the app finished itself after it was
  // killed carries "Recovered automatically", and the summary showed no note
  // at all. Only Edit had it.
  testWidgets("a run's note is on its summary", (tester) async {
    _useTallPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RunSummaryScreen(
          summary: RunSummary(
            startedAt: DateTime(2026, 9, 29, 7, 12),
            duration: const Duration(minutes: 10),
            distanceMeters: 1990,
            notes: kRecoveredRunNote,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NOTES'), findsOneWidget);
    expect(find.text(kRecoveredRunNote), findsOneWidget);
  });

  testWidgets('and a run with nothing written has no notes heading', (
    tester,
  ) async {
    _useTallPhone(tester);
    for (final notes in <String?>[null, '', '   ']) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RunSummaryScreen(
            summary: RunSummary(
              startedAt: DateTime(2026, 9, 29, 7, 12),
              duration: const Duration(minutes: 10),
              distanceMeters: 1990,
              notes: notes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('NOTES'), findsNothing, reason: '"$notes"');
    }
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

  group('a run just finished is an arrival, not a record being looked up', () {
    // The field test's finding, in one sentence: the run "was recorded,
    // displayed, and then disappeared". `_finish()` popped, so an hour of
    // effort ended with the screen going away. This screen was always the one
    // built to receive it — its own entrance comment says it arrives the
    // instant a run ends — and nothing ever routed to it.

    testWidgets('says so in the title', (tester) async {
      _useTallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RunSummaryScreen(summary: withData, justFinished: true),
        ),
      );

      expect(find.text('Run complete'), findsOneWidget);
      expect(find.text('Run summary'), findsNothing);
    });

    testWidgets('and does not file it under a date it does not need', (
      tester,
    ) async {
      // Stamping `21 Jul 2026, 07:32` on a run somebody finished thirty
      // seconds ago is the one sentence a log entry needs and this reader
      // already knows.
      _useTallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RunSummaryScreen(summary: withData, justFinished: true),
        ),
      );

      expect(find.textContaining('Just now'), findsOneWidget);
      expect(find.textContaining('21 Jul 2026'), findsNothing);
    });

    testWidgets('while the same run out of the log keeps its date', (
      tester,
    ) async {
      _useTallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RunSummaryScreen(summary: withData),
        ),
      );

      expect(find.textContaining('21 Jul 2026'), findsOneWidget);
      expect(find.textContaining('Just now'), findsNothing);
    });
  });

  group('the way back to the coach', () {
    testWidgets('is offered even when the coach had nothing to say', (
      tester,
    ) async {
      // Silence is a normal output of `RunNote` — most runs are ordinary — and
      // a runner who wants to know what their coach makes of an ordinary run
      // should not have to go and find the conversation to ask.
      _useTallPhone(tester);
      var asked = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RunSummaryScreen(summary: withData, onAskCoach: () => asked++),
        ),
      );

      final button = find.text('Ask your coach about this run');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();
      expect(asked, 1);
    });

    testWidgets('and is absent when there is no coach behind it', (
      tester,
    ) async {
      // Absent rather than inert. A control that cannot do anything is worse
      // than no control — the same rule the Done button already follows.
      _useTallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RunSummaryScreen(summary: withData),
        ),
      );

      expect(find.text('Ask your coach about this run'), findsNothing);
    });
  });

  group('the measures a running app tracks', () {
    testWidgets('the figures Strava had and we did not', (tester) async {
      // The 23 Aug 10 km, as Strava summarised it: 167 m of gain, a 111 m high
      // point, 8,468 steps. Ours showed none of the three.
      _useTallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RunSummaryScreen(
            summary: RunSummary(
              startedAt: DateTime(2026, 7, 21, 7, 32),
              duration: const Duration(minutes: 57, seconds: 47),
              distanceMeters: 10010,
              elevationGainMeters: 167,
              elevationMaxMeters: 111,
              steps: 8468,
            ),
          ),
        ),
      );

      expect(find.text('STEPS'), findsOneWidget);
      // Grouped, because a step count is the one figure here that runs to five
      // digits and `8468` is not a number anybody reads at a glance.
      expect(find.text('8,468'), findsOneWidget);
      // Named apart. A bare "ELEVATION" was unambiguous while gain was the only
      // elevation figure on the screen; beside a high point it is not.
      expect(find.text('ELEVATION GAIN'), findsOneWidget);
      expect(find.text('167 m'), findsOneWidget);
      expect(find.text('MAX ELEVATION'), findsOneWidget);
      expect(find.text('111 m'), findsOneWidget);
    });

    testWidgets('a flat run shows a high point and no gain', (tester) async {
      // Two absences that do not mean the same thing: no gain worth reporting
      // is a flat run, and it still has a summit.
      _useTallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RunSummaryScreen(
            summary: RunSummary(
              startedAt: DateTime(2026, 7, 21, 7, 32),
              duration: const Duration(minutes: 27),
              distanceMeters: 5230,
              elevationMaxMeters: 18,
            ),
          ),
        ),
      );

      expect(find.text('ELEVATION GAIN'), findsNothing);
      expect(find.text('MAX ELEVATION'), findsOneWidget);
      expect(find.text('18 m'), findsOneWidget);
    });

    testWidgets('and no tile at all when there are none', (tester) async {
      // A denied Health read is indistinguishable from no data, so absence is
      // an absent tile — never a zero and never an error (CLAUDE.md rule 6).
      // The same rule covers the elevation pair, which is absent on every run
      // this app records until there is a barometer to ask (ADR-0024).
      _useTallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RunSummaryScreen(
            summary: RunSummary(
              startedAt: DateTime(2026, 7, 21, 7, 32),
              duration: const Duration(minutes: 27, seconds: 45),
              distanceMeters: 5230,
              avgHr: 148,
            ),
          ),
        ),
      );

      expect(find.text('STEPS'), findsNothing);
      expect(find.text('ELEVATION GAIN'), findsNothing);
      expect(find.text('MAX ELEVATION'), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(find.text('0 m'), findsNothing);
    });
  });

  testWidgets('draws the route, with a pin per kilometre', (tester) async {
    // A run opened from the log has never drawn a route: the old Supabase read
    // returned summaries and the `fetchRunDetail` beside it was dead code, so
    // the map on this screen only ever appeared for a run handed to it in
    // memory. Given a trace, the pins come off the same walk as the splits.
    _useTallPhone(tester);
    final start = DateTime(2026, 7, 21, 7, 32);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RunSummaryScreen(
          summary: RunSummary(
            startedAt: start,
            duration: const Duration(minutes: 12),
            distanceMeters: 2335,
            // ~111.19 m per hop along the equator: two whole kilometres and a
            // bit, so two pins.
            points: <RunPoint>[
              for (var i = 0; i <= 21; i++)
                RunPoint(
                  latitude: 0,
                  longitude: i * 0.001,
                  accuracyMeters: 5,
                  timestamp: start.add(Duration(seconds: i * 5)),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(RouteMap), findsOneWidget);
    expect(
      tester.widget<RouteMap>(find.byType(RouteMap)).splitMarkers,
      hasLength(2),
    );
  });
}
