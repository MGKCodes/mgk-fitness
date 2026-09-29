import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';
import 'package:mgk_lift/src/features/tracking/presentation/active_session_screen.dart';
import 'package:mgk_lift/src/features/tracking/presentation/session_summary_screen.dart';
import 'package:mgk_lift/src/features/tracking/presentation/finish_sheet.dart';

final DateTime _day = DateTime(2026, 8, 6, 18);

Session _finished({
  String name = 'Push',
  List<SessionExercise> exercises = const <SessionExercise>[],
}) => Session(
  id: 'today',
  name: name,
  startedAt: _day,
  endedAt: _day.add(const Duration(minutes: 47)),
  exercises: exercises,
);

SessionSet _set(
  String id,
  int number,
  double kg,
  int reps, {
  SetType type = SetType.working,
  bool done = true,
}) => SessionSet(
  id: id,
  setNumber: number,
  weightKg: kg,
  reps: reps,
  isCompleted: done,
  setType: type,
);

/// The summary as a pushed route, so back has somewhere to land — which is how
/// the app reaches it, and the only way to test that leaving it works.
Widget _pushed(SessionSummaryScreen screen) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => screen)),
          child: const Text('Track'),
        ),
      ),
    ),
  ),
);

void main() {
  group('what the summary says', () {
    testWidgets('names the session and reports the four totals', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: _finished(
              exercises: <SessionExercise>[
                SessionExercise(
                  id: 'e1',
                  name: 'Barbell Bench Press',
                  orderIndex: 0,
                  sets: <SessionSet>[
                    _set('s1', 1, 60, 10, type: SetType.warmup),
                    _set('s2', 2, 80, 8),
                    _set('s3', 3, 85, 6),
                  ],
                ),
                const SessionExercise(
                  id: 'e2',
                  name: 'Cable Fly',
                  orderIndex: 1,
                ),
                const SessionExercise(
                  id: 'e3',
                  name: 'Cable Tricep Pushdown',
                  orderIndex: 2,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SESSION COMPLETE'), findsOneWidget);
      expect(find.text('Push'), findsOneWidget);

      // Read off the StatBlocks rather than by searching for the numbers,
      // because each figure has to be checked **against its own label**. A
      // bare `find.text('2')` cannot tell the set count from the second set's
      // row marker, and it is exactly a mismatched label and value — `1410
      // kg3` — that got through this app's tests once already.
      //
      // The volume is 80×8 + 85×6: the warm-up is out, the same as in the
      // running header, so the numbers a lifter watched climb are the ones
      // they land on.
      expect(
        <String>[
          for (final stat in tester.widgetList<StatBlock>(
            find.byType(StatBlock),
          ))
            '${stat.label} ${stat.value}',
        ],
        <String>['Duration 47:00', 'Volume 1150 kg', 'Sets 2', 'Movements 3'],
      );
    });

    testWidgets('lists the sets that were logged and marks the warm-ups', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: _finished(
              exercises: <SessionExercise>[
                SessionExercise(
                  id: 'e1',
                  name: 'Barbell Bench Press',
                  orderIndex: 0,
                  sets: <SessionSet>[
                    _set('s1', 1, 60, 10, type: SetType.warmup),
                    _set('s2', 2, 85, 6),
                    // Added and never ticked. It did not happen, so a record
                    // of what happened must not list it.
                    _set('s3', 3, 85, 6, done: false),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('60 kg × 10'), findsOneWidget);
      expect(find.text('85 kg × 6'), findsOneWidget);
      // The same `W` the live row carries. Without it the screen contradicts
      // itself: three ticks above a header saying one working set, and no way
      // to tell which was discounted.
      expect(find.text('W'), findsOneWidget);
    });

    testWidgets('says nothing was logged on a movement that was skipped', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: _finished(
              exercises: const <SessionExercise>[
                SessionExercise(id: 'e1', name: 'Cable Fly', orderIndex: 0),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // It counted as a movement, so dropping it would leave the count above
      // disagreeing with the list.
      expect(find.text('Cable Fly'), findsOneWidget);
      expect(find.text('Nothing logged'), findsOneWidget);
    });
  });

  group('personal bests', () {
    Session bench(double kg, int reps) => _finished(
      exercises: <SessionExercise>[
        SessionExercise(
          id: 'e1',
          name: 'Barbell Bench Press',
          orderIndex: 0,
          sets: <SessionSet>[_set('s1', 1, kg, reps)],
        ),
      ],
    );

    final List<Session> log = <Session>[
      Session(
        id: 'old',
        name: 'Push',
        startedAt: _day.subtract(const Duration(days: 7)),
        endedAt: _day.subtract(const Duration(days: 7, hours: -1)),
        exercises: <SessionExercise>[
          SessionExercise(
            id: 'oe1',
            name: 'Barbell Bench Press',
            orderIndex: 0,
            sets: <SessionSet>[_set('os1', 1, 90, 5)],
          ),
        ],
      ),
    ];

    testWidgets('names the set that did it and what it beat', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(session: bench(100, 5), log: log),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NEW BEST'), findsOneWidget);
      // The set that happened first, then the estimate — and the estimate is
      // hedged, because Epley is a fitted line rather than a measurement.
      expect(find.text('100 kg × 5 — around 116.5 kg for one'), findsOneWidget);
      expect(find.text('Past 105 kg, set 30 Jul'), findsOneWidget);
    });

    testWidgets('a session that beat nothing says so, and nothing more', (
      tester,
    ) async {
      // The ordinary session. It is not a failure and must not be dressed as
      // one — one quiet line, no panel and no encouragement.
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(session: bench(85, 5), log: log),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No new bests today.'), findsOneWidget);
      expect(find.text('NEW BEST'), findsNothing);
      expect(find.text('NEW BESTS'), findsNothing);
    });

    testWidgets('a session above the rep cap says it could not tell', (
      tester,
    ) async {
      // Two different facts: "we compared and nothing beat your best", and
      // "there was nothing here to compare". Rendering them the same would
      // tell a lifter who trained in fifteens that they went backwards.
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: _finished(
              exercises: <SessionExercise>[
                SessionExercise(
                  id: 'e1',
                  name: 'Dumbbell Bicep Curl',
                  orderIndex: 0,
                  sets: <SessionSet>[_set('s1', 1, 14, 15)],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('can only be estimated up to 12 reps'),
        findsOneWidget,
      );
      expect(find.text('No new bests today.'), findsNothing);
    });
  });

  group('leaving', () {
    testWidgets('back to Track pops the summary', (tester) async {
      await tester.pumpWidget(
        _pushed(SessionSummaryScreen(session: _finished())),
      );
      await tester.tap(find.text('Track'));
      await tester.pumpAndSettle();
      expect(find.text('SESSION COMPLETE'), findsOneWidget);

      await tester.tap(find.text('Back to Track'));
      await tester.pumpAndSettle();

      expect(find.text('SESSION COMPLETE'), findsNothing);
      expect(find.text('Track'), findsOneWidget);
    });

    testWidgets('the coach action is absent without a coach', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SessionSummaryScreen(session: _finished())),
      );
      await tester.pumpAndSettle();

      // Absent rather than inert: there is no coach in a free or offline
      // build, and a button that opens nothing is worse than no button.
      expect(find.text('Talk it over with your coach'), findsNothing);
    });

    testWidgets('opening the coach leaves the summary first', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        _pushed(
          SessionSummaryScreen(
            session: _finished(),
            onOpenCoach: () => opened = true,
          ),
        ),
      );
      await tester.tap(find.text('Track'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Talk it over with your coach'));
      await tester.pumpAndSettle();

      // The coach is a sheet over the surface you were on, and its gates
      // redirect rather than refuse. Opening it from on top of the summary
      // would hide both behind a screen the lifter has finished with.
      expect(opened, isTrue);
      expect(find.text('SESSION COMPLETE'), findsNothing);
    });
  });

  group('keeping the session', () {
    testWidgets('the offer is absent when there is nowhere to save', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: _finished(
              exercises: const <SessionExercise>[
                SessionExercise(id: 'e1', name: 'Cable Fly', orderIndex: 0),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save to your workouts'), findsNothing);
    });

    testWidgets('saving names the workout and then stops asking', (
      tester,
    ) async {
      final library = InMemoryWorkoutLibrary();
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: _finished(
              name: 'Evening session',
              exercises: const <SessionExercise>[
                SessionExercise(
                  id: 'e1',
                  name: 'Barbell Bench Press',
                  orderIndex: 0,
                ),
                SessionExercise(id: 'e2', name: 'Cable Fly', orderIndex: 1),
              ],
            ),
            library: library,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save to your workouts'));
      await tester.pumpAndSettle();

      // The same dialog the running screen opens, because it is literally the
      // same function.
      expect(find.text('Name this workout'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Chest day');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect((await library.all()).single.movementNames, <String>[
        'Barbell Bench Press',
        'Cable Fly',
      ]);

      // The write, the haptic and the snackbar are all awaited before the
      // screen rebuilds, so the frame has to be pumped again after them —
      // without this the assertions below read the tree as it stood before
      // the save returned.
      await tester.pumpAndSettle();

      // The offer becomes a statement. Leaving the button there invites a
      // second copy of the same workout.
      expect(find.text('Save to your workouts'), findsNothing);
      expect(find.text('Saved as Chest day.'), findsOneWidget);
    });
  });

  group('finishing routes through it', () {
    late AppDatabase db;
    late DriftSessionRecorder recorder;
    var counter = 0;

    setUp(() {
      counter = 0;
      db = AppDatabase.memory();
      recorder = DriftSessionRecorder(db, idFactory: () => 'id-${++counter}');
    });

    tearDown(() async => db.close());

    Future<Widget> screen({WorkoutLibrary? withLibrary}) async {
      await recorder.start(name: 'Push');
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet('id-3', reps: 5, weightKg: 100);
      await recorder.updateSet('id-3', isCompleted: true);
      final session = await recorder.current();
      return MaterialApp(
        home: ActiveSessionScreen(
          recorder: recorder,
          session: session!,
          library: withLibrary,
        ),
      );
    }

    testWidgets('finishing opens the summary instead of popping', (
      tester,
    ) async {
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await finishSession(tester);

      expect(find.byType(SessionSummaryScreen), findsOneWidget);
      expect(find.text('SESSION COMPLETE'), findsOneWidget);
      // The session that `finish()` returned, not the one the screen was
      // holding: it has an `endedAt`, so it has a duration and can be compared
      // against the log at all.
      expect(find.text('100 kg × 5'), findsOneWidget);
    });

    testWidgets('the finished session screen is replaced, not covered', (
      tester,
    ) async {
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await finishSession(tester);

      // Left underneath, it would be a session that no longer exists: its
      // clock would tick and its Finish button would call `finish()` on a
      // recorder with nothing open.
      expect(find.byType(ActiveSessionScreen), findsNothing);
      expect(find.text('In progress'), findsNothing);
    });

    testWidgets('the save offer moves to the summary rather than blocking it', (
      tester,
    ) async {
      final library = InMemoryWorkoutLibrary();
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      await finishSession(tester);

      // No dialog in front of the answer. The offer is on the screen the
      // lifter was going to read anyway, where declining it costs nothing.
      expect(find.text('Name this workout'), findsNothing);
      expect(find.text('Save to your workouts'), findsOneWidget);
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
