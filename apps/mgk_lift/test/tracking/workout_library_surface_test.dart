import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/tracking/data/exercise_lookup.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/stats/data/drift_session_history.dart';
import 'package:mgk_lift/src/features/tracking/domain/exercise.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';
import 'package:mgk_lift/src/features/tracking/presentation/active_session_screen.dart';
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

/// Something inside the library row for [name].
Finder inRow(String name, Finder what) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(AppCard)).first,
  matching: what,
);

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

  /// From an empty session: the library, then the row's own button, which
  /// fills the session with it — no preview between.
  Future<void> useWorkout(WidgetTester tester, String name) async {
    await tester.tap(find.text('Your workouts'));
    await tester.pumpAndSettle();
    await tester.tap(inRow(name, find.widgetWithText(SmallPill, 'Use')));
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

    testWidgets('an empty library offers the three starters, and no builder', (
      tester,
    ) async {
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Your workouts'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing saved yet'), findsOneWidget);
      // R11: three starting points, where one is needed, instead of a
      // catalogue; R5: nothing is built from a blank page.
      for (final split in <String>['Full Body', 'Upper / Lower', 'PPL']) {
        expect(inRow(split, find.byType(SmallPill)), findsOneWidget);
      }
      expect(find.text('Build one'), findsNothing);
      expect(find.text('Browse ready-made'), findsNothing);
    });
  });

  group('starting a session from a saved workout', () {
    testWidgets('a tap opens the row to every set; nothing starts', (
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

      // The whole workout, set by set, in the row — what the preview sheet
      // showed, without the sheet.
      expect(find.text('4 × 6'), findsOneWidget);
      expect(find.text('3 sets'), findsOneWidget);
      expect((await recorder.current())!.exercises, isEmpty);
    });

    testWidgets('Use fills the session, every set laid out', (tester) async {
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

  group('Finish asks about the workout (R3, R4)', () {
    Finder inSheet(Finder what) =>
        find.descendant(of: find.byType(FinishSheet), matching: what);

    /// Finish in the header, the question answered as asked, then Finish on
    /// the sheet.
    Future<void> finishWith(
      WidgetTester tester, {
      bool? save,
      String? name,
    }) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish').first);
      await tester.pumpAndSettle();
      if (save != null) {
        final toggle = tester.widget<Switch>(inSheet(find.byType(Switch)));
        if (toggle.value != save) {
          await tester.tap(inSheet(find.byType(Switch)));
          await tester.pumpAndSettle();
        }
      }
      if (name != null) {
        await tester.enterText(inSheet(find.byType(TextField)), name);
        await tester.pumpAndSettle();
      }
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Finish')));
      await tester.pumpAndSettle();
    }

    Future<SavedWorkout> push() => library.save(
      name: 'Push',
      movements: moves(<String>['Barbell Bench Press', 'Cable Fly']),
    );

    testWidgets('a movement taken out: asked, on, and yes takes it out', (
      tester,
    ) async {
      await push();
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Finish').first);
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Save to Push for next time')), findsOneWidget);
      expect(inSheet(find.text('− Cable Fly')), findsOneWidget);
      // The answer most people want, already set.
      expect(tester.widget<Switch>(inSheet(find.byType(Switch))).value, isTrue);
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Finish')));
      await tester.pumpAndSettle();

      expect((await library.all()).single.movementNames, <String>[
        'Barbell Bench Press',
      ]);
      expect(find.text('Push is updated for next time.'), findsOneWidget);
    });

    testWidgets('started from Track, the same', (tester) async {
      // The one-tap start goes through TrackController, not the session
      // screen's own library button.
      final saved = await push();
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

      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);
      await finishWith(tester);

      expect((await library.all()).single.movementNames, <String>[
        'Barbell Bench Press',
      ]);
    });

    testWidgets('switched off, the workout stays as it was', (tester) async {
      await push();
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);
      await finishWith(tester, save: false);

      expect(
        (await library.all()).single.movements,
        moves(<String>['Barbell Bench Press', 'Cable Fly']),
      );
    });

    testWidgets('skipping sets or movements asks nothing', (tester) async {
      await push();
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      // One set of bench and nothing else: a short day, not a new workout.
      await logFirstSet(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Finish').first);
      await tester.pumpAndSettle();
      expect(inSheet(find.byType(Switch)), findsNothing);
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Finish')));
      await tester.pumpAndSettle();

      expect(
        (await library.all()).single.movements,
        moves(<String>['Barbell Bench Press', 'Cable Fly']),
      );
    });

    testWidgets('edited on another phone: asked, off, so nothing is lost', (
      tester,
    ) async {
      final saved = await push();
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);
      // Edited elsewhere while this session ran.
      final edited = saved.copyWith(
        movements: const <TemplateMovement>[
          TemplateMovement('Barbell Bench Press', sets: 5),
          TemplateMovement('Cable Fly'),
        ],
      );
      await library.update(edited);

      await tester.tap(find.widgetWithText(FilledButton, 'Finish').first);
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Save to Push anyway')), findsOneWidget);
      expect(
        inSheet(find.textContaining('changed on another phone')),
        findsOneWidget,
      );
      expect(
        tester.widget<Switch>(inSheet(find.byType(Switch))).value,
        isFalse,
      );
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Finish')));
      await tester.pumpAndSettle();

      expect((await library.all()).single.movements, edited.movements);
    });

    testWidgets('edited on another phone, and on: the edit is replaced', (
      tester,
    ) async {
      final saved = await push();
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);
      await library.update(
        saved.copyWith(
          movements: const <TemplateMovement>[
            TemplateMovement('Barbell Bench Press', sets: 5),
            TemplateMovement('Cable Fly'),
          ],
        ),
      );
      await finishWith(tester, save: true);

      expect((await library.all()).single.movements, const <TemplateMovement>[
        TemplateMovement('Barbell Bench Press'),
      ]);
    });

    testWidgets('deleted meanwhile: offered as a new workout, off', (
      tester,
    ) async {
      final saved = await push();
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);
      await library.remove(saved.id);

      await tester.tap(find.widgetWithText(FilledButton, 'Finish').first);
      await tester.pumpAndSettle();
      expect(
        inSheet(find.text("Save today's session as a new workout")),
        findsOneWidget,
      );
      expect(
        inSheet(find.textContaining('was deleted while you trained')),
        findsOneWidget,
      );
      expect(
        tester.widget<Switch>(inSheet(find.byType(Switch))).value,
        isFalse,
      );
      await tester.tap(inSheet(find.byType(Switch)));
      await tester.pumpAndSettle();
      // Named for the workout it was, and editable.
      expect(inSheet(find.widgetWithText(TextField, 'Push')), findsOneWidget);
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Finish')));
      await tester.pumpAndSettle();

      final all = await library.all();
      expect(all.single.name, 'Push');
      expect(all.single.movementNames, <String>['Barbell Bench Press']);
    });

    testWidgets('a blank session: Save as a workout, off', (tester) async {
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet('id-3', reps: 5, weightKg: 100);
      await recorder.updateSet('id-3', isCompleted: true);
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Finish').first);
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Save as a workout')), findsOneWidget);
      expect(
        tester.widget<Switch>(inSheet(find.byType(Switch))).value,
        isFalse,
      );
      // No name asked for until it is wanted.
      expect(inSheet(find.byType(TextField)), findsNothing);
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Finish')));
      await tester.pumpAndSettle();

      expect(await library.all(), isEmpty);
    });

    testWidgets('switched on, it is kept under the name typed, each once', (
      tester,
    ) async {
      // Coming back to the bench at the end makes one workout with bench in
      // it, not one with bench in it twice.
      await recorder.start(name: 'Evening session');
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet('id-3', reps: 5, weightKg: 100);
      await recorder.updateSet('id-3', isCompleted: true);
      await recorder.addExercise('Cable Fly');
      await recorder.addSet('id-4');
      await recorder.updateSet('id-5', reps: 12, weightKg: 20);
      await recorder.updateSet('id-5', isCompleted: true);
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-6');
      await recorder.updateSet('id-7', reps: 5, weightKg: 90);
      await recorder.updateSet('id-7', isCompleted: true);
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Finish').first);
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.byType(Switch)));
      await tester.pumpAndSettle();
      // Pre-filled with the session's name.
      expect(
        inSheet(find.widgetWithText(TextField, 'Evening session')),
        findsOneWidget,
      );
      await tester.enterText(inSheet(find.byType(TextField)), 'Chest day');
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Finish')));
      await tester.pumpAndSettle();

      final saved = (await library.all()).single;
      expect(saved.name, 'Chest day');
      expect(saved.movements, const <TemplateMovement>[
        TemplateMovement('Barbell Bench Press', sets: 1),
        TemplateMovement('Cable Fly', sets: 1),
      ]);
      // Saved by hand, not added from one of the fifteen.
      expect(saved.premadeId, isNull);
      expect(find.text('Chest day is in your workouts.'), findsOneWidget);
    });

    testWidgets('the running list no longer offers to save', (tester) async {
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Discard session'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Save to your workouts'), findsNothing);
    });

    testWidgets('editing a past session never asks', (tester) async {
      await push();
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();
      await useWorkout(tester, 'Push');
      await tester.tap(find.byTooltip('Remove Cable Fly'));
      await tester.pumpAndSettle();
      await logFirstSet(tester);
      await finishWith(tester, save: false);
      final finished = (await DriftSessionHistory(db).all()).single;

      // The same session, opened again to correct it, with a set added and
      // left unticked — so Done has something to say about it.
      final editor = DriftSessionRecorder.editing(db, finished.id);
      // A new app, not the old one with a new home: the old navigator would
      // keep the summary on top.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: ActiveSessionScreen(
            recorder: editor,
            session: finished,
            lookup: _lookup,
            library: library,
            editing: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Its one movement is done, so its card starts folded.
      await tester.tap(find.text('Barbell Bench Press').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add set').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Done').first);
      await tester.pumpAndSettle();

      expect(find.byType(FinishSheet), findsOneWidget);
      expect(inSheet(find.byType(Switch)), findsNothing);
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Save')));
      await tester.pumpAndSettle();
      expect(
        (await library.all()).single.movements,
        moves(<String>['Barbell Bench Press', 'Cable Fly']),
      );
    });
  });

  group('the starters', () {
    Future<void> openEmpty(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutLibraryScreen(library: library, lookup: _lookup),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('adding one writes every session in it, each a copy', (
      tester,
    ) async {
      await openEmpty(tester);

      await tester.tap(inRow('PPL', find.widgetWithText(SmallPill, 'Add')));
      await tester.pumpAndSettle();

      final saved = await library.all();
      expect(saved.map((w) => w.name).toSet(), <String>{
        'Push',
        'Pull',
        'Legs',
      });
      // Copies that remember where they came from, carrying the movements
      // rather than pointing at them.
      expect(saved.map((w) => w.premadeId), everyElement(isNotNull));
      expect(saved.map((w) => w.movements), everyElement(isNotEmpty));
      expect(find.text('PPL added: 3 workouts.'), findsOneWidget);
      // And they are the list now, each startable.
      expect(find.widgetWithText(SmallPill, 'Start'), findsNWidgets(3));
    });

    testWidgets('an add can be undone, back to the starters', (tester) async {
      await openEmpty(tester);
      await tester.tap(
        inRow('Full Body', find.widgetWithText(SmallPill, 'Add')),
      );
      await tester.pumpAndSettle();
      expect(await library.all(), hasLength(1));

      await tester.tap(find.widgetWithText(TextButton, 'Undo'));
      await tester.pumpAndSettle();

      expect(await library.all(), isEmpty);
      expect(find.text('Nothing saved yet'), findsOneWidget);
    });
  });

  group('the library screen', () {
    /// Opens the library from a host, so what it pops with can be read.
    Future<List<LibraryOutcome?>> openLibrary(
      WidgetTester tester, {
      String? openSessionName,
      String? openAt,
      bool offerBlank = false,
    }) async {
      final popped = <LibraryOutcome?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => popped.add(
                    await WorkoutLibraryScreen.open(
                      context,
                      library: library,
                      lookup: _lookup,
                      openSessionName: openSessionName,
                      openAt: openAt,
                      offerBlank: offerBlank,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return popped;
    }

    Future<void> more(WidgetTester tester, String name, String action) async {
      await tester.tap(find.byTooltip('More for $name'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, action));
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

    testWidgets('a tap opens the row, and a second closes it', (tester) async {
      await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[
          TemplateMovement('A', sets: 4, repTarget: 6),
        ],
      );
      await openLibrary(tester);
      expect(find.text('4 × 6'), findsNothing);

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      expect(find.text('4 × 6'), findsOneWidget);

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      expect(find.text('4 × 6'), findsNothing);
    });

    testWidgets('opened at a workout, its row is already open', (tester) async {
      await library.save(
        name: 'Pull',
        movements: const <TemplateMovement>[
          TemplateMovement('B', sets: 5, repTarget: 5),
        ],
      );
      final push = await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[
          TemplateMovement('A', sets: 4, repTarget: 6),
        ],
      );
      await openLibrary(tester, openAt: push.id);

      expect(find.text('4 × 6'), findsOneWidget);
      expect(find.text('5 × 5'), findsNothing);
    });

    testWidgets('Start leaves with the workout; nothing else to answer', (
      tester,
    ) async {
      final push = await library.save(
        name: 'Push',
        movements: moves(<String>['A']),
      );
      final popped = await openLibrary(tester);

      await tester.tap(find.widgetWithText(SmallPill, 'Start'));
      await tester.pumpAndSettle();

      final outcome = popped.single! as StartWorkout;
      expect(outcome.workout.id, push.id);
      expect(outcome.discardingOpen, isFalse);
    });

    testWidgets('opened to start something: a blank session leads', (
      tester,
    ) async {
      // What Track's Start a session meant before it opened this screen, one
      // tap away and above everything saved (TR2, TR8).
      await library.save(name: 'Push', movements: moves(<String>['A']));
      final popped = await openLibrary(tester, offerBlank: true);

      expect(
        tester.getTopLeft(find.text('Blank session')).dy,
        lessThan(tester.getTopLeft(find.text('Push')).dy),
      );
      await tester.tap(
        inRow('Blank session', find.widgetWithText(SmallPill, 'Start')),
      );
      await tester.pumpAndSettle();
      expect(popped.single, isA<StartBlank>());
    });

    testWidgets('nothing saved: blank, then the three starters', (
      tester,
    ) async {
      await openLibrary(tester, offerBlank: true);
      expect(find.text('Blank session'), findsOneWidget);
      expect(find.text('Nothing saved yet'), findsOneWidget);
      expect(find.text('PPL'), findsOneWidget);
    });

    testWidgets('filling a running session, there is no blank to offer', (
      tester,
    ) async {
      await library.save(name: 'Push', movements: moves(<String>['A']));
      await openLibrary(tester);
      expect(find.text('Blank session'), findsNothing);
    });

    testWidgets('nor with a session open, which it would have to discard', (
      tester,
    ) async {
      await library.save(name: 'Push', movements: moves(<String>['A']));
      await openLibrary(tester, offerBlank: true, openSessionName: 'Legs');
      expect(find.text('Blank session'), findsNothing);
    });

    testWidgets('no photographs: the list is for reading (TR8)', (
      tester,
    ) async {
      await openLibrary(tester, offerBlank: true);
      expect(find.byType(PhotoBackdrop), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('with a session open, Start asks: resume it', (tester) async {
      await library.save(name: 'Push', movements: moves(<String>['A']));
      final popped = await openLibrary(tester, openSessionName: 'Legs');

      await tester.tap(find.widgetWithText(SmallPill, 'Start'));
      await tester.pumpAndSettle();
      // Both named: which one is open is the whole question.
      expect(find.text('Legs is still open'), findsOneWidget);
      expect(find.textContaining('start Push?'), findsOneWidget);

      await tester.tap(find.text('Resume Legs'));
      await tester.pumpAndSettle();
      expect(popped.single, isA<ResumeOpen>());
    });

    testWidgets('with a session open, Start asks: discard it and start', (
      tester,
    ) async {
      await library.save(name: 'Push', movements: moves(<String>['A']));
      final popped = await openLibrary(tester, openSessionName: 'Legs');

      await tester.tap(find.widgetWithText(SmallPill, 'Start'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard it'));
      await tester.pumpAndSettle();

      final outcome = popped.single! as StartWorkout;
      expect(outcome.workout.name, 'Push');
      expect(outcome.discardingOpen, isTrue);
    });

    testWidgets('cancelling the question leaves everything as it was', (
      tester,
    ) async {
      await library.save(name: 'Push', movements: moves(<String>['A']));
      final popped = await openLibrary(tester, openSessionName: 'Legs');

      await tester.tap(find.widgetWithText(SmallPill, 'Start'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(popped, isEmpty);
      expect(find.text('Push'), findsOneWidget);
    });

    testWidgets('deleting asks, then offers Undo', (tester) async {
      await library.save(name: 'Push', movements: moves(<String>['A']));
      await openLibrary(tester);

      await more(tester, 'Push', 'Delete');

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

      await more(tester, 'Push', 'Delete');
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

      await more(tester, 'Push', 'Duplicate');

      final all = await library.all();
      expect(all.map((w) => w.name), <String>['Push (2)', 'Push']);
      expect(all.first.movements, all.last.movements);
      expect(find.text('Push (2)'), findsOneWidget);
    });

    testWidgets('Edit opens the editor on that workout', (tester) async {
      await library.save(name: 'Push', movements: moves(<String>['A']));
      await openLibrary(tester);

      await more(tester, 'Push', 'Edit');

      expect(find.text('Edit workout'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Push'), findsOneWidget);
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
