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
      expect(find.text('Add a ready-made one'), findsOneWidget);
      expect(find.text('Build one'), findsOneWidget);
    });
  });

  group('starting a session from a saved workout', () {
    testWidgets('picking one fills the session with its movements', (
      tester,
    ) async {
      await library.save(
        name: 'Push',
        movements: <String>['Barbell Bench Press', 'Cable Fly'],
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Your workouts'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      // The session is now the workout: movements in, in order, and named
      // after it.
      final session = (await recorder.current())!;
      expect(session.name, 'Push');
      expect(session.exercises.map((e) => e.name), <String>[
        'Barbell Bench Press',
        'Cable Fly',
      ]);

      // And the empty state is gone, which is what the lifter sees.
      expect(find.text('The clock is running'), findsNothing);
    });

    testWidgets('the back-reference is written to the session row', (
      tester,
    ) async {
      final saved = await library.save(
        name: 'Push',
        movements: <String>['Barbell Bench Press'],
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your workouts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      final row = await db.select(db.workouts).getSingle();
      expect(row.templateId, saved.id);
      expect(row.premadeId, isNull);
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
      expect(saved.single.movements, <String>[
        'Barbell Bench Press',
        'Cable Fly',
      ]);
      // Saved by hand, not added from one of the fifteen.
      expect(saved.single.premadeId, isNull);
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

      // Three movement cards push the footer actions below the fold.
      await tester.scrollUntilVisible(
        find.text('Save to your workouts'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save to your workouts'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect((await library.all()).single.movements, <String>[
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

      expect((await library.all()).single.movements, <String>[
        'Barbell Bench Press',
      ]);
    });

    testWidgets('a session started from the library is not offered again', (
      tester,
    ) async {
      await library.save(
        name: 'Push',
        movements: <String>['Barbell Bench Press'],
      );

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your workouts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      // A saved workout brings movements and no sets, so the first tap adds
      // the set the lifter is about to do. A tick needs reps, so they go in
      // first.
      await tester.tap(find.text('Add first set'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '5');
      await leaveField(tester);
      await tester.tap(find.byTooltip('Mark done'));
      await tester.pumpAndSettle();

      await finishSession(tester);

      // They already have this workout. Offering them a copy of something they
      // picked off a list ninety minutes ago is the app not paying attention —
      // which is why the summary is handed no library at all rather than
      // deciding for itself.
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

    testWidgets('adding one writes a copy with a back-reference', (
      tester,
    ) async {
      await tester.pumpWidget(premadeSheet(library));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

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

    testWidgets('adding a split adds every session in it', (tester) async {
      await tester.pumpWidget(premadeSheet(library));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add all 3 to your library').first);
      await tester.pumpAndSettle();

      final saved = await library.all();
      expect(saved, hasLength(3));
      expect(saved.map((w) => w.premadeId).toSet(), hasLength(3));
    });

    testWidgets('a premade already in the library is marked', (tester) async {
      await library.save(
        name: 'Push',
        movements: <String>['Barbell Bench Press'],
        fromPremade: 'push',
      );

      await tester.pumpWidget(premadeSheet(library));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Not a lock — a second Push is allowed. This only answers the question
      // somebody scrolling fifteen of them is actually asking.
      await tester.scrollUntilVisible(
        find.byTooltip('Add Push to your library'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('In your library'), findsWidgets);
    });
  });

  group('the library sheet', () {
    testWidgets('lists what is saved, newest first', (tester) async {
      await library.save(name: 'Push', movements: <String>['A']);
      await library.save(name: 'Pull', movements: <String>['B']);

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your workouts'));
      await tester.pumpAndSettle();

      expect(find.text('Push'), findsOneWidget);
      expect(find.text('Pull'), findsOneWidget);

      final pull = tester.getTopLeft(find.text('Pull')).dy;
      final push = tester.getTopLeft(find.text('Push')).dy;
      expect(pull, lessThan(push));
    });

    testWidgets('deleting one takes it out of the list', (tester) async {
      await library.save(name: 'Push', movements: <String>['A']);

      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your workouts'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete Push'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(await library.all(), isEmpty);
      expect(find.text('Nothing saved yet'), findsOneWidget);
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
