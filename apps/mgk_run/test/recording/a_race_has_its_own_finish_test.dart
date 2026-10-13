import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_history.dart';
import 'package:mgk_run/src/features/recording/domain/best_effort.dart';
import 'package:mgk_run/src/features/recording/domain/run_race.dart';
import 'package:mgk_run/src/features/recording/domain/run_split.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/recording/presentation/run_summary_screen.dart';

/// **A race has its own finish** (ADR-0049).
///
/// The run that started this was a half marathon recorded as an ordinary 21.69
/// km: the distance in large, "Furthest you've been", and twenty-two split rows
/// with a dash at the end of each. These tests pin the other screen — the time
/// first, the chip time beside the phone's, the halves, the plan behind it —
/// and the two fixes every run gets: splits folded, and no column of dashes.
void main() {
  const half = 21097.5;
  const perKm = <int>[
    323, 307, 309, 302, 292, 306, 339, 320, 326, 311, //
    347, 325, 356, 346, 338, 356, 346, 349, 353, 355, 371,
  ];
  final splits = <RunSplit>[
    for (var i = 0; i < perKm.length; i++)
      RunSplit(
        index: i + 1,
        distanceMeters: 1000,
        duration: Duration(seconds: perKm[i]),
      ),
    const RunSplit(
      index: 22,
      distanceMeters: 685.8,
      duration: Duration(seconds: 260),
    ),
  ];

  RunSummary sunday({RunRace? race}) => RunSummary(
    id: 'sunday',
    startedAt: DateTime(2026, 10, 11, 9, 31),
    duration: const Duration(hours: 2, minutes: 0, seconds: 47),
    distanceMeters: 21685.8,
    steps: 16575,
    splits: splits,
    bestEfforts: const <BestEffort>[
      BestEffort(
        distanceMeters: 5000,
        duration: Duration(minutes: 25, seconds: 16),
      ),
      BestEffort(
        distanceMeters: 10000,
        duration: Duration(minutes: 52, seconds: 4),
      ),
      BestEffort(
        distanceMeters: half,
        duration: Duration(hours: 1, minutes: 57, seconds: 40),
      ),
    ],
    race: race,
  );

  const official = RunRace(
    distanceMeters: half,
    officialTime: Duration(hours: 2, minutes: 0, seconds: 30),
    name: 'Royal Parks Half',
  );

  Future<void> pump(
    WidgetTester tester,
    RunSummary run, {
    Future<RaceSaveOutcome?> Function(RunRace?)? onSave,
    LabelledPlan? plan,
    List<RunSummary> history = const <RunSummary>[],
  }) async {
    tester.view.physicalSize = const Size(400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RunSummaryScreen(
          summary: run,
          history: history,
          onSaveRace: onSave,
          racePlan: plan,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a race', () {
    testWidgets('leads with the official time, over the course distance', (
      tester,
    ) async {
      await pump(tester, sunday(race: official));

      expect(find.text('Race summary'), findsOneWidget);
      expect(find.text('2:00:30'), findsOneWidget);
      // 2:00:30 over 21.0975 km, not over the phone's 21.69.
      expect(find.text('Half marathon  ·  5:43 /km'), findsOneWidget);
      expect(find.textContaining('Royal Parks Half'), findsOneWidget);
    });

    testWidgets("says what the phone had, and that it isn't a fault", (
      tester,
    ) async {
      await pump(tester, sunday(race: official));

      expect(
        find.textContaining('Your phone had 2:00:47 over 21.69 km'),
        findsOneWidget,
      );
    });

    testWidgets('without an official time, offers to add one', (tester) async {
      await pump(
        tester,
        sunday(race: const RunRace(distanceMeters: half)),
        onSave: (_) async => RaceSaveOutcome.saved,
      );

      expect(find.text('2:00:47'), findsOneWidget);
      expect(find.textContaining('phone’s time'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('is called a first, and keeps its half-marathon time single', (
      tester,
    ) async {
      await pump(tester, sunday(race: official));

      expect(find.text('Your first half marathon.'), findsOneWidget);
      // The 5K and 10K inside it are records; the phone's 1:57:40 "half" is
      // not shown beside the real one.
      expect(find.text('Fastest 5K and 10K yet'), findsOneWidget);
      expect(find.text('1:57:40'), findsNothing);
    });

    testWidgets('shows how it was run, half by half and 5K by 5K', (
      tester,
    ) async {
      await pump(tester, sunday(race: official));

      expect(find.text('HOW YOU RAN IT'), findsOneWidget);
      expect(find.text('FIRST HALF'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);
      expect(
        find.textContaining('The biggest drop came after 10K.'),
        findsOneWidget,
      );
    });

    testWidgets('has no training section without a plan', (tester) async {
      await pump(tester, sunday(race: official));
      expect(find.text('THE TRAINING'), findsNothing);
    });

    testWidgets('and has one when a plan was aimed at it', (tester) async {
      final plan = LabelledPlan(
        record: PlanRecord(
          id: 'p',
          startDate: DateTime(2026, 7, 20),
          weeks: 12,
          isActive: false,
          goalDistanceMeters: half,
          eventDate: DateTime(2026, 10, 11),
        ),
        label: 'Half marathon plan',
      );
      await pump(
        tester,
        sunday(race: official),
        plan: plan,
        history: <RunSummary>[
          RunSummary(
            startedAt: DateTime(2026, 9, 27, 8),
            duration: const Duration(hours: 1, minutes: 40),
            distanceMeters: 18000,
          ),
        ],
      );

      expect(find.text('THE TRAINING'), findsOneWidget);
      expect(find.text('Half marathon plan · 12 weeks'), findsOneWidget);
      expect(find.text('LONGEST'), findsOneWidget);
    });
  });

  group('a training run', () {
    testWidgets('that looks like a race is asked whether it was one', (
      tester,
    ) async {
      await pump(tester, sunday(), onSave: (_) async => RaceSaveOutcome.saved);

      expect(find.text('Run summary'), findsOneWidget);
      expect(find.text('Was this a race?'), findsOneWidget);
    });

    testWidgets('is not asked when there is nowhere to save it', (
      tester,
    ) async {
      await pump(tester, sunday());
      expect(find.text('Was this a race?'), findsNothing);
      expect(find.text('Mark as a race'), findsNothing);
    });

    testWidgets('becomes a race in place once it is marked', (tester) async {
      RunRace? saved;
      await pump(
        tester,
        sunday(),
        onSave: (race) async {
          saved = race;
          return RaceSaveOutcome.saved;
        },
      );

      await tester.tap(find.text('Was this a race?'));
      await tester.pumpAndSettle();
      // The sheet starts on the half, with the phone's time in the wheels.
      expect(find.text('Save race · 2:00:47'), findsOneWidget);
      await tester.tap(find.text('Save race · 2:00:47'));
      await tester.pumpAndSettle();

      expect(saved?.distanceMeters, half);
      // Left as the phone had it, so no official time is claimed.
      expect(saved?.officialTime, isNull);
      expect(find.text('Race summary'), findsOneWidget);
      expect(find.text('Your first half marathon.'), findsOneWidget);
    });

    testWidgets('stays as it was when the save fails', (tester) async {
      await pump(tester, sunday(), onSave: (_) async => null);

      await tester.tap(find.text('Was this a race?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save race · 2:00:47'));
      await tester.pumpAndSettle();

      expect(find.text('Run summary'), findsOneWidget);
      expect(find.textContaining('could not be saved'), findsOneWidget);
    });
  });

  group('splits', () {
    testWidgets('fold to the fastest and slowest on a long run', (
      tester,
    ) async {
      await pump(tester, sunday());

      expect(find.text('Show all 22 splits'), findsOneWidget);
      expect(find.text('Fastest'), findsOneWidget);
      expect(find.text('km 5'), findsOneWidget); // 4:52
      expect(find.text('km 21'), findsOneWidget); // 6:11, not the 0.69 km
      expect(find.text('6:19 /km'), findsNothing);

      await tester.tap(find.text('Show all 22 splits'));
      await tester.pumpAndSettle();
      expect(find.text('6:19 /km'), findsOneWidget);
      expect(find.text('Hide splits'), findsOneWidget);
    });

    testWidgets('carry no column of dashes when there is no heart rate', (
      tester,
    ) async {
      await pump(tester, sunday());
      await tester.tap(find.text('Show all 22 splits'));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsNothing);
    });
  });
}
