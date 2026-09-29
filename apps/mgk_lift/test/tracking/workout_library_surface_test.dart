import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/tracking/data/exercise_lookup.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/exercise.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';
import 'package:mgk_lift/src/features/tracking/presentation/active_session_screen.dart';
import 'package:mgk_lift/src/features/tracking/presentation/premade_library_sheet.dart';
import 'package:mgk_lift/src/features/tracking/presentation/finish_sheet.dart';
import 'package:mgk_lift/src/features/tracking/presentation/track_controller.dart';
import 'package:mgk_lift/src/features/tracking/presentation/workout_library_screen.dart';

/// A three-entry catalogue. The real one is 266 movements and loading it into
/// every widget test is work no assertion here depends on.
final ExerciseLookup _lookup = ExerciseLookup(<Exercise>[
  const Exercise(
    name: 'Barbell Bench Press',
    category: 'Barbell',
    muscleGroup: 'Chest',
    equipment: 'Barbell',
    imageKey: 'barbell-bench-press',
  ),
  const Exercise(
    name: 'Cable Fly',
    category: 'Cable',
    muscleGroup: 'Chest',
    equipment: 'Cable',
    imageKey: 'cable-fly',
  ),
  const Exercise(
    name: 'Barbell Back Squat',
    category: 'Barbell',
    muscleGroup: 'Legs',
    equipment: 'Barbell',
    imageKey: 'barbell-back-squat',
  ),
]);

/// Names as movements with the default count.
List<TemplateMovement> moves(List<String> names) => <TemplateMovement>[
  for (final n in names) TemplateMovement(n),
];

void main() {
  late AppDatabase db;
  late DriftSessionRecorder recorder;
  late InMemoryWorkoutLibrary library;
  var counter = 0;

  setUp(() {
    counter = 0;
    db = AppDatabase.memory();
    recorder = DriftSessionRecorder(db, idFactory: () => 'id-${++counter}');
    library = InMemoryWorkoutLibrary();
  });

  tearDown(() async => db.close());

  Future<Widget> screen({WorkoutLibrary? withLibrary}) async {
    final session = await recorder.current() ?? await recorder.start();
    return MaterialApp(
      home: ActiveSessionScreen(
        recorder: recorder,
        session: session,
        lookup: _lookup,
        library: withLibrary,
      ),
    );
  }

  /// From an empty session: the library, the workout's preview, then the
  /// button that fills the session with it.
  Future<void> useWorkout(WidgetTester tester, String name) async {
    await tester.tap(find.text('Your workouts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this workout'));
    await tester.pumpAndSettle();
  }

  /// Types reps into the first set and ticks it.
  Future<void> logFirstSet(WidgetTester tester) async {
    // Weight, then reps, per set — so the reps of the first set are field 1.
    await tester.enterText(find.byType(TextField).at(1), '5');
    await leaveField(tester);
    await tester.tap(find.byTooltip('Mark done').first);
    await tester.pumpAndSettle();
  }

  group('the empty state', () {
    testWidgets('offers the library, not the app template picker', (
      tester,
    ) async {
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      // The whole point of retiring `_useTemplate`: the second action on a
      // blank session opens the lifter's own saved workouts, and there is no
      // longer any route from here straight into one of the fifteen.
      expect(find.text('Your workouts'), findsOneWidget);
      expect(find.text('Use a template'), findsNothing);
    });

    testWidgets('hides the library action when there is no library', (
      tester,
    ) async {
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      // A build with no on-device database. An action that cannot work is
      // worse than no action.
      expect(find.text('Your workouts'), findsNothing);
      expect(find.text('Add exercise'), findsOneWidget);
    });

    testWidgets('an empty library leads with the ready-made list', (
      tester,
    ) async {
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Your workouts'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing saved yet'), findsOneWidget);
      // A blank builder is the same blank page the library exists to solve, so
      // it is the quieter of the two.
      expect(
        find.widgetWithText(FilledButton, 'Browse ready-made'),
        findsOneWidget,
      );
      expect(find.text('Build one'), findsOneWidget);
    });
  });

  group('starting a session from a saved workout', () {
    testWidgets('a tap previews it; nothing starts until asked', (
      tester,
    ) async {
      await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[
          TemplateMovement('Barbell Bench Press', sets: 4, repTarget: 6),
          TemplateMovement('Cable Fly'),
        ],
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your workouts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      // The whole workout, set by set, before the clock starts.
      expect(find.text('4 × 6'), findsOneWidget);
      expect(find.text('3 sets'), findsOneWidget);
      expect((await recorder.current())!.exercises, isEmpty);
    });

    testWidgets('Use this workout fills the session, every set laid out', (
      tester,
    ) async {
      await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[
          TemplateMovement('Barbell Bench Press', sets: 4, repTarget: 6),
          TemplateMovement('Cable Fly'),
        ],
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');

      // The session is now the workout: movements in, in order, named after
      // it, and the sets already there — it used to open as empty cards.
      final session = (await recorder.current())!;
      expect(session.name, 'Push');
      expect(session.exercises.map((e) => e.name), <String>[
        'Barbell Bench Press',
        'Cable Fly',
      ]);
      expect(session.exercises.map((e) => e.sets.length), <int>[4, 3]);
      expect(find.text('Add first set'), findsNothing);
      expect(find.text('The clock is running'), findsNothing);
    });

    testWidgets('the session remembers the workout, and how it was', (
      tester,
    ) async {
      final saved = await library.save(
        name: 'Push',
        movements: moves(<String>['Barbell Bench Press']),
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');

      final row = await db.select(db.workouts).getSingle();
      expect(row.templateId, saved.id);
      expect(row.premadeId, isNull);
      // What Finish compares the session with, to teach the workout.
      expect(TemplateMovement.decode(row.templateSnapshot), saved.movements);
    });
  });

  group('the workout learns from the session', () {
    testWidgets('a movement removed today is removed from the workout', (
      tester,
    ) async {
      await library.save(
        name: 'Push',
        movements: moves(<String>['Barbell Bench Press', 'Cable Fly']),
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');

      // The request this exists for: take the fly out once, and it is out next
      // week too, without redoing the workout.
      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);
      await finishSession(tester);

      expect(find.text('Push updated — removed Cable Fly.'), findsOneWidget);
      expect((await library.all()).single.movementNames, <String>[
        'Barbell Bench Press',
      ]);
      // The session's own "Cable Fly removed. Undo" did not follow it here.
      expect(find.text('Cable Fly removed.'), findsNothing);
    });

    testWidgets('started from Track, the same: it learns, and offers no copy', (
      tester,
    ) async {
      // The one-tap start goes through TrackController, not the session
      // screen's own library button — and the harness showed that path losing
      // the link on its way to the summary. Pinned here with the real recorder.
      final saved = await library.save(
        name: 'Push',
        movements: moves(<String>['Barbell Bench Press', 'Cable Fly']),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => TrackController(
                    recorder,
                    library: library,
                  ).openWorkout(context, saved),
                  child: const Text('Start from Track'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start from Track'));
      await tester.pumpAndSettle();

      expect(find.text('Add first set'), findsNothing, reason: 'laid out');
      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);
      await finishSession(tester);

      expect(find.text('Push updated — removed Cable Fly.'), findsOneWidget);
      expect(find.text('Save to your workouts'), findsNothing);
      expect((await library.all()).single.movementNames, <String>[
        'Barbell Bench Press',
      ]);
    });

    testWidgets('Undo on the summary puts the workout back', (tester) async {
      await library.save(
        name: 'Push',
        movements: moves(<String>['Barbell Bench Press', 'Cable Fly']),
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);
      await finishSession(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Push kept as it was.'), findsOneWidget);
      expect((await library.all()).single.movementNames, <String>[
        'Barbell Bench Press',
        'Cable Fly',
      ]);
    });

    testWidgets('skipping sets or movements changes nothing', (tester) async {
      await library.save(
        name: 'Push',
        movements: moves(<String>['Barbell Bench Press', 'Cable Fly']),
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      // One set of bench and nothing else: a short day, not a new workout.
      await logFirstSet(tester);
      await finishSession(tester);

      expect(find.textContaining('updated'), findsNothing);
      expect(
        (await library.all()).single.movements,
        moves(<String>['Barbell Bench Press', 'Cable Fly']),
      );
    });

    testWidgets('a workout edited meanwhile is asked about, not overwritten', (
      tester,
    ) async {
      final saved = await library.save(
        name: 'Push',
        movements: moves(<String>['Barbell Bench Press', 'Cable Fly']),
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);

      // Edited elsewhere — another device — while this session ran.
      await library.update(
        saved.copyWith(
          movements: const <TemplateMovement>[
            TemplateMovement('Barbell Bench Press', sets: 5),
            TemplateMovement('Cable Fly'),
          ],
        ),
      );
      await finishSession(tester);

      expect(find.textContaining('changed while you trained'), findsOneWidget);
      // Nothing applied until they say so.
      expect((await library.all()).single.movementCount, 2);

      await tester.tap(find.widgetWithText(TextButton, 'Update'));
      await tester.pumpAndSettle();
      expect((await library.all()).single.movementNames, <String>[
        'Barbell Bench Press',
      ]);
    });

    testWidgets('a workout deleted meanwhile can be kept as a new one', (
      tester,
    ) async {
      final saved = await library.save(
        name: 'Push',
        movements: moves(<String>['Barbell Bench Press', 'Cable Fly']),
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);
      await library.remove(saved.id);
      await finishSession(tester);

      expect(
        find.textContaining('was deleted while you trained'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save as new'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect((await library.all()).single.movementNames, <String>[
        'Barbell Bench Press',
      ]);
    });
  });

  group('saving a session to the library', () {
    testWidgets('the action appears once the session has movements', (
      tester,
    ) async {
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      expect(find.text('Save to your workouts'), findsOneWidget);
    });

    testWidgets('saving writes the movements under the confirmed name', (
      tester,
    ) async {
      await recorder.start(name: 'Evening session');
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addExercise('Cable Fly');

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save to your workouts'));
      await tester.pumpAndSettle();

      // Pre-filled with the session's name and selected, so the common answer
      // is one tap.
      expect(find.widgetWithText(TextField, 'Evening session'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Chest day');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = await library.all();
      expect(saved, hasLength(1));
      expect(saved.single.name, 'Chest day');
      expect(saved.single.movementNames, <String>[
        'Barbell Bench Press',
        'Cable Fly',
      ]);
      // Saved by hand, not added from one of the fifteen.
      expect(saved.single.premadeId, isNull);
    });

    testWidgets('once saved, the offer becomes a statement', (tester) async {
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to your workouts'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // A second tap used to make a second copy.
      expect(find.text('Save to your workouts'), findsNothing);
      expect(find.text('Saved to your workouts'), findsOneWidget);
    });

    testWidgets('a session from a saved workout is not offered as a copy', (
      tester,
    ) async {
      await library.save(
        name: 'Push',
        movements: moves(<String>['Barbell Bench Press']),
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      await tester.scrollUntilVisible(
        find.text('Discard session'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      // The workout learns from this session at Finish; a save here made a
      // second one.
      expect(find.text('Save to your workouts'), findsNothing);
    });

    testWidgets('cancelling saves nothing', (tester) async {
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save to your workouts'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(await library.all(), isEmpty);
    });

    testWidgets('a movement done twice is saved once', (tester) async {
      // Coming back to the bench at the end makes one workout with bench in
      // it, not one with bench in it twice.
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addExercise('Cable Fly');
      await recorder.addExercise('Barbell Bench Press');

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      // Three movement cards push the footer actions below the fold — and the
      // list runs on under the glass dock, so it is brought to the middle of
      // the screen, where a thumb would bring it, before it is tapped.
      await tester.scrollUntilVisible(
        find.text('Save to your workouts'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Save to your workouts')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to your workouts'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect((await library.all()).single.movementNames, <String>[
        'Barbell Bench Press',
        'Cable Fly',
      ]);
    });

    testWidgets('finishing a session offers to keep it, on the summary', (
      tester,
    ) async {
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet('id-3', reps: 5, weightKg: 100);
      await recorder.updateSet('id-3', isCompleted: true);

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      await finishSession(tester);

      // Still the only moment the app knows a session worked — but the offer
      // is now a button on the summary rather than a dialog fired in front of
      // it. Saving is something you decide about the shape of a session after
      // seeing it, and until the summary existed there was nowhere to see it.
      expect(find.text('Name this workout'), findsNothing);
      await tester.tap(find.text('Save to your workouts'));
      await tester.pumpAndSettle();

      expect(find.text('Name this workout'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // As many sets as were worked.
      expect((await library.all()).single.movements, const <TemplateMovement>[
        TemplateMovement('Barbell Bench Press', sets: 1),
      ]);
    });

    testWidgets('a session started from the library is not offered again', (
      tester,
    ) async {
      await library.save(
        name: 'Push',
        movements: moves(<String>['Barbell Bench Press']),
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      await logFirstSet(tester);
      await finishSession(tester);

      // They already have this workout. Offering them a copy of something they
      // picked off a list ninety minutes ago is the app not paying attention —
      // the workout learns from the session instead.
      expect(find.text('Name this workout'), findsNothing);
      expect(find.text('Save to your workouts'), findsNothing);
      expect(await library.all(), hasLength(1));
    });
  });

  group('adding a premade', () {
    Widget premadeSheet(WorkoutLibrary library) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  PremadeLibrarySheet.show(context, library: library),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    Future<void> scrollToPush(WidgetTester tester) async {
      // The Sessions list sits below all eight splits.
      await tester.scrollUntilVisible(
        find.byTooltip('Add Push to your library'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      // `scrollUntilVisible` stops the moment the row enters the tree, which
      // can leave it on the bottom edge; this brings it fully into view.
      await tester.ensureVisible(find.byTooltip('Add Push to your library'));
      await tester.pumpAndSettle();
    }

    testWidgets('adding one writes a copy with a back-reference', (
      tester,
    ) async {
      await tester.pumpWidget(premadeSheet(library));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await scrollToPush(tester);
      // Offered six first, so Push leads the section.
      await tester.tap(find.byTooltip('Add Push to your library').first);
      await tester.pumpAndSettle();

      final saved = await library.all();
      expect(saved, hasLength(1));
      expect(saved.single.name, 'Push');
      expect(saved.single.premadeId, 'push');
      // A copy, so it carries the premade's movements rather than pointing at
      // them.
      expect(saved.single.movements, isNotEmpty);
    });

    testWidgets('an add can be undone, from inside the sheet', (tester) async {
      await tester.pumpWidget(premadeSheet(library));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await scrollToPush(tester);
      await tester.tap(find.byTooltip('Add Push to your library').first);
      await tester.pumpAndSettle();

      // The Undo is in the sheet's own messenger. On the screen's it sat
      // behind the sheet, where nobody could reach it.
      final undo = find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Undo'),
      );
      expect(undo.hitTestable(), findsOneWidget);
      await tester.tap(undo);
      await tester.pumpAndSettle();

      expect(await library.all(), isEmpty);
      // And the row offers the plain add again.
      expect(find.byTooltip('Add Push to your library'), findsOneWidget);
    });

    testWidgets('adding a split adds every session in it', (tester) async {
      await tester.pumpWidget(premadeSheet(library));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add all 3 to your library').first);
      await tester.pumpAndSettle();

      final saved = await library.all();
      expect(saved, hasLength(3));
      expect(saved.map((w) => w.premadeId).toSet(), hasLength(3));
      expect(find.text('3 workouts added.'), findsOneWidget);
    });

    testWidgets(
      'a premade already in the library needs an explicit second add',
      (tester) async {
        await library.save(
          name: 'Push',
          movements: moves(<String>['Barbell Bench Press']),
          fromPremade: 'push',
        );

        await tester.pumpWidget(premadeSheet(library));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final again = find.widgetWithText(TextButton, 'Add again');
        await tester.scrollUntilVisible(
          again,
          400,
          scrollable: find.byType(Scrollable).first,
        );
        // Aligned by the button, not the subtitle: `ensureVisible` puts the top
        // of what it is given at the top of the list, and the subtitle's top
        // left the button's centre just outside it.
        await tester.ensureVisible(again.first);
        await tester.pumpAndSettle();

        // Tapping the row no longer quietly makes `Push (2)`.
        await tester.tap(find.text('In your library').first);
        await tester.pumpAndSettle();
        expect(await library.all(), hasLength(1));

        // Not a lock — a second Push is allowed, when asked for by name.
        await tester.tap(again.first);
        await tester.pumpAndSettle();
        expect((await library.all()).map((w) => w.name), contains('Push (2)'));
      },
    );
  });

  group('the library screen', () {
    Future<void> openLibrary(WidgetTester tester, {String? blocked}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutLibraryScreen(
            library: library,
            lookup: _lookup,
            blockedReason: blocked,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists what is saved, newest first', (tester) async {
      await library.save(name: 'Push', movements: moves(<String>['A']));
      await library.save(name: 'Pull', movements: moves(<String>['B']));

      await openLibrary(tester);

      expect(find.text('Push'), findsOneWidget);
      expect(find.text('Pull'), findsOneWidget);

      final pull = tester.getTopLeft(find.text('Pull')).dy;
      final push = tester.getTopLeft(find.text('Push')).dy;
      expect(pull, lessThan(push));
    });

    testWidgets('deleting asks, then offers Undo', (tester) async {
      await library.save(name: 'Push', movements: moves(<String>['A']));
      await openLibrary(tester);

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Push?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(await library.all(), isEmpty);
      expect(find.text('Nothing saved yet'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Undo'));
      await tester.pumpAndSettle();
      expect((await library.all()).single.name, 'Push');
      expect(find.text('Push'), findsOneWidget);
    });

    testWidgets('keeping it deletes nothing', (tester) async {
      await library.save(name: 'Push', movements: moves(<String>['A']));
      await openLibrary(tester);

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Keep it'));
      await tester.pumpAndSettle();

      expect(await library.all(), hasLength(1));
    });

    testWidgets('duplicating adds a copy under a free name', (tester) async {
      await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[
          TemplateMovement('A', sets: 4, repTarget: 6),
        ],
      );
      await openLibrary(tester);

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Duplicate'));
      await tester.pumpAndSettle();

      final all = await library.all();
      expect(all.map((w) => w.name), <String>['Push (2)', 'Push']);
      expect(all.first.movements, all.last.movements);
      expect(find.text('Push (2)'), findsOneWidget);
    });

    testWidgets('with a session open, Start says why it cannot', (
      tester,
    ) async {
      await library.save(name: 'Push', movements: moves(<String>['A']));
      await openLibrary(tester, blocked: 'Finish the session you have open.');

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      expect(find.text('Finish the session you have open.'), findsOneWidget);
      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start'),
      );
      expect(start.onPressed, isNull);
    });
  });
}

/// Finishes the session on screen: Finish in the header, then Finish on the
/// sheet that now asks first.
Future<void> finishSession(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Finish').first);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(FinishSheet),
      matching: find.widgetWithText(FilledButton, 'Finish'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Leaves the focused field, which is when its value is saved.
Future<void> leaveField(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}
