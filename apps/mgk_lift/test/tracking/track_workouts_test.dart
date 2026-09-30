import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/stats/data/drift_session_history.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_template.dart';
import 'package:mgk_lift/src/features/tracking/presentation/finish_sheet.dart';
import 'package:mgk_lift/src/features/tracking/presentation/track_surface.dart';

/// "Your workouts" on Track: the library one tap from the front page, rather
/// than only from inside a session whose clock was already running.
void main() {
  final today = DateTime(2026, 9, 29, 18);

  final push = SavedWorkout(
    id: 'push',
    name: 'Push',
    movements: const <TemplateMovement>[
      TemplateMovement('Barbell Bench Press', sets: 4, repTarget: 6),
      TemplateMovement('Cable Fly'),
    ],
    savedAt: DateTime(2026, 9, 1),
  );
  final pull = SavedWorkout(
    id: 'pull',
    name: 'Pull',
    movements: const <TemplateMovement>[TemplateMovement('Barbell Row')],
    savedAt: DateTime(2026, 9, 2),
  );

  Future<void> pump(
    WidgetTester tester, {
    List<SavedWorkout> workouts = const <SavedWorkout>[],
    ValueChanged<SavedWorkout>? onStart,
    VoidCallback? onOpenLibrary,
    Session? openSession,
    List<Session> log = const <Session>[],
    VoidCallback? onResume,
    ValueChanged<SavedWorkout>? onDiscardAndStart,
    ValueChanged<WorkoutSplit>? onAddStarter,
  }) async {
    // A tall phone. Track's action pill is anchored at the foot and floats
    // over the page, so in the default 800x600 test window it sat on top of
    // the cards' Start buttons and took their taps.
    tester.view.physicalSize = const Size(430 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackSurface(
            today: today,
            workouts: workouts,
            onStartWorkout: onStart,
            onOpenLibrary: onOpenLibrary,
            openSession: openSession,
            log: log,
            onStartSession: onResume,
            onDiscardAndStart: onDiscardAndStart,
            onAddStarter: onAddStarter,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the saved workouts sit on Track, with a way to all of them', (
    tester,
  ) async {
    await pump(
      tester,
      workouts: <SavedWorkout>[pull, push],
      onOpenLibrary: () {},
    );

    expect(find.text('YOUR WORKOUTS'), findsOneWidget);
    expect(find.text('Pull'), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('2 movements · 7 sets'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('a card says when the workout was last done', (tester) async {
    await pump(
      tester,
      workouts: <SavedWorkout>[push],
      onOpenLibrary: () {},
      log: <Session>[
        Session(
          id: 's',
          name: 'Push',
          templateId: 'push',
          startedAt: DateTime(2026, 9, 23, 18),
          endedAt: DateTime(2026, 9, 23, 19),
        ),
      ],
    );
    expect(find.text('Last done 23 Sep'), findsOneWidget);
  });

  testWidgets('none saved: the three starting points take the row', (
    tester,
  ) async {
    WorkoutSplit? added;
    await pump(tester, onOpenLibrary: () {}, onAddStarter: (s) => added = s);

    expect(find.text('START FROM ONE OF THESE'), findsOneWidget);
    expect(find.text('Full Body'), findsOneWidget);
    expect(find.text('Upper / Lower'), findsOneWidget);
    await tester.tap(find.text('Add').first);
    expect(added?.id, 'full-body');
  });

  testWidgets('none saved and nothing to offer: says how to get one', (
    tester,
  ) async {
    await pump(tester, onOpenLibrary: () {});
    expect(find.textContaining('save it as a workout'), findsOneWidget);
  });

  testWidgets('with no library there is no section at all', (tester) async {
    await pump(tester, workouts: <SavedWorkout>[push]);
    expect(find.text('YOUR WORKOUTS'), findsNothing);
    expect(find.text('Push'), findsNothing);
  });

  testWidgets('Start on a card starts it, with no preview between', (
    tester,
  ) async {
    SavedWorkout? started;
    await pump(
      tester,
      workouts: <SavedWorkout>[push],
      onOpenLibrary: () {},
      onStart: (w) => started = w,
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(started, push);
  });

  testWidgets('with a session open, Start asks: resume it, or discard it', (
    tester,
  ) async {
    SavedWorkout? started;
    var resumed = 0;
    await pump(
      tester,
      workouts: <SavedWorkout>[push],
      onOpenLibrary: () {},
      onStart: (w) => started = w,
      onResume: () => resumed++,
      openSession: Session(
        id: 'open',
        name: 'Legs',
        startedAt: today.subtract(const Duration(minutes: 20)),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    // In the question, not only in Track's headline, which says it too.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Legs is still open'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Resume Legs'),
      ),
    );
    await tester.pumpAndSettle();
    expect(resumed, 1);
    expect(started, isNull, reason: 'a second session never starts over one');
  });

  testWidgets('discarding the open one starts the one asked for', (
    tester,
  ) async {
    SavedWorkout? replaced;
    await pump(
      tester,
      workouts: <SavedWorkout>[push],
      onOpenLibrary: () {},
      onStart: (_) {},
      onResume: () {},
      onDiscardAndStart: (w) => replaced = w,
      openSession: Session(
        id: 'open',
        name: 'Legs',
        startedAt: today.subtract(const Duration(minutes: 20)),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard it'));
    await tester.pumpAndSettle();
    expect(replaced, push);
  });

  testWidgets('the card itself opens the library', (tester) async {
    var opened = 0;
    await pump(
      tester,
      workouts: <SavedWorkout>[push],
      onOpenLibrary: () => opened++,
      onStart: (_) {},
    );

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  group('in the shell', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.memory());
    tearDown(() async => db.close());

    testWidgets('the row follows the library, whoever changed it', (
      tester,
    ) async {
      final library = InMemoryWorkoutLibrary();
      final saved = await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[
          TemplateMovement('Barbell Bench Press'),
          TemplateMovement('Cable Fly'),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: LiftShell(library: library)));
      await tester.pumpAndSettle();
      expect(find.text('2 movements · 6 sets'), findsOneWidget);

      // Not through anything the shell opened.
      await library.update(
        saved.copyWith(
          movements: const <TemplateMovement>[
            TemplateMovement('Barbell Bench Press'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 movement · 3 sets'), findsOneWidget);
    });

    testWidgets('a workout taught at Finish is taught on Track too', (
      tester,
    ) async {
      // The whole trip, as found on the emulator: Track said "4 movements"
      // about a workout the summary had just taken one out of.
      final library = InMemoryWorkoutLibrary();
      await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[
          TemplateMovement('Barbell Bench Press'),
          TemplateMovement('Cable Fly'),
        ],
      );
      var n = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LiftShell(
            recorder: DriftSessionRecorder(db, idFactory: () => 'r-${++n}'),
            history: DriftSessionHistory(db),
            library: library,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '5');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mark done').first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Finish').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(FinishSheet),
          matching: find.widgetWithText(FilledButton, 'Finish'),
        ),
      );
      await tester.pumpAndSettle();
      // Asked at Finish now (R3), on by default, and said as it is done.
      expect(find.text('Push is updated for next time.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('1 movement · 3 sets'), findsOneWidget);
    });
  });
}
