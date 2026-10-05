import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/stats/presentation/exercise_stats_screen.dart';
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

      expect(find.text('Session complete'), findsOneWidget);
      // When and what, as Run's says "Just now · Outdoor run".
      expect(find.text('Just now  ·  Push'), findsOneWidget);

      // Read off the StatBlocks rather than by searching for the numbers,
      // because each figure has to be checked **against its own label**. A
      // bare `find.text('2')` cannot tell the set count from the second set's
      // row marker, and it is exactly a mismatched label and value — `1410
      // kg3` — that got through this app's tests once already.
      //
      // The volume is 80×8 + 85×6: the warm-up is out, the same as in the
      // running header, so the numbers a lifter watched climb are the ones
      // they land on. It leads, large, and the other three sit under it.
      expect(
        find.descendant(
          of: find.byType(GlassSurface),
          matching: find.text('1150 kg'),
        ),
        findsOneWidget,
      );
      expect(
        <String>[
          for (final stat in tester.widgetList<StatBlock>(
            find.byType(StatBlock),
          ))
            '${stat.label} ${stat.value}',
        ],
        <String>['Duration 47:00', 'Sets 2', 'Movements 3'],
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

    testWidgets('the mark says the new best, then closes (13, R7)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: bench(100, 5),
            log: log,
            onOpenCoach: () {},
          ),
        ),
      );
      // Mid-sentence: typed out, and held long enough to read.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('New best: Barbell Bench Press'), findsOneWidget);
      // The set that happened first, then the estimate — hedged, because
      // Epley is a fitted line rather than a measurement.
      expect(find.textContaining('100 kg × 5, about'), findsOneWidget);
      expect(find.textContaining('Past 105 kg'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('New best: Barbell Bench Press'), findsNothing);
      expect(find.byType(CoachButton), findsOneWidget);
    });

    testWidgets('a session that beat nothing says nothing at all', (
      tester,
    ) async {
      // The ordinary session. It is not a failure and must not be dressed as
      // one, and the mark is not there to fill the silence.
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: bench(85, 5),
            log: log,
            onOpenCoach: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1500));

      expect(find.textContaining('New best'), findsNothing);
      expect(find.textContaining('new bests'), findsNothing);
      expect(find.byType(CoachButton), findsOneWidget);
    });
  });

  group('leaving', () {
    testWidgets('Done pops the summary', (tester) async {
      await tester.pumpWidget(
        _pushed(SessionSummaryScreen(session: _finished())),
      );
      await tester.tap(find.text('Track'));
      await tester.pumpAndSettle();
      expect(find.text('Session complete'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      expect(find.text('Session complete'), findsNothing);
      expect(find.text('Track'), findsOneWidget);
    });

    testWidgets('the mark is absent without a coach', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SessionSummaryScreen(session: _finished())),
      );
      await tester.pumpAndSettle();

      // Absent rather than inert: there is no coach in an offline build, and
      // a mark that opens nothing is worse than no mark.
      expect(find.byType(CoachButton), findsNothing);
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

      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();

      // The coach is a sheet over the surface you were on, and its gates
      // redirect rather than refuse. Opening it from on top of the summary
      // would hide both behind a screen the lifter has finished with.
      expect(opened, isTrue);
      expect(find.text('Session complete'), findsNothing);
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
      expect(find.text('Session complete'), findsOneWidget);
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

    testWidgets('nothing is left to answer on the summary (R4)', (
      tester,
    ) async {
      final library = InMemoryWorkoutLibrary();
      await tester.pumpWidget(await screen(withLibrary: library));
      await tester.pumpAndSettle();

      await finishSession(tester);

      // Asked at Finish, so the summary has one exit and no offer.
      expect(find.text('Save to your workouts'), findsNothing);
      expect(find.text('Name this workout'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    });
  });

  group("a movement's name", () {
    testWidgets('opens its stats, with this session counted', (tester) async {
      tester.view
        ..physicalSize = const Size(1179, 5000)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: _finished(
              exercises: <SessionExercise>[
                SessionExercise(
                  id: 'e1',
                  name: 'Barbell Bench Press',
                  orderIndex: 0,
                  sets: <SessionSet>[_set('s1', 1, 120, 6)],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Barbell Bench Press'));
      await tester.pumpAndSettle();

      expect(find.byType(ExerciseStatsScreen), findsOneWidget);
      // 120 × (1 + 6/30): the session just finished is in it.
      expect(find.text('144 kg'), findsWidgets);
    });

    testWidgets('goes where the caller says, when it says', (tester) async {
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: _finished(
              exercises: <SessionExercise>[
                SessionExercise(
                  id: 'e1',
                  name: 'Barbell Bench Press',
                  orderIndex: 0,
                  sets: <SessionSet>[_set('s1', 1, 120, 6)],
                ),
              ],
            ),
            onOpenMovement: (name) => opened = name,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Barbell Bench Press'));
      await tester.pumpAndSettle();

      expect(opened, 'Barbell Bench Press');
      expect(find.byType(ExerciseStatsScreen), findsNothing);
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
