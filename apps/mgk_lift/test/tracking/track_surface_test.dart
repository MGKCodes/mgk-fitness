import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan.dart';
import 'package:mgk_lift/src/features/stats/data/drift_session_history.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';
import 'package:mgk_lift/src/features/tracking/presentation/active_session_screen.dart';
import 'package:mgk_lift/src/features/tracking/presentation/track_surface.dart';
import 'package:mgk_lift/src/features/tracking/presentation/workout_library_screen.dart';

/// Track as a front page (docs/lift-2.0.0-track.md): the Today card and its
/// button, the week as days and times, and the last session.
void main() {
  // A Thursday, at half past six.
  final now = DateTime(2026, 10, 1, 18, 30);

  Session finished(
    String name,
    DateTime at, {
    int minutes = 60,
    int sets = 3,
    String id = '',
  }) => Session(
    id: id.isEmpty ? '$name-${at.day}-${at.hour}' : id,
    name: name,
    startedAt: at,
    endedAt: at.add(Duration(minutes: minutes)),
    exercises: <SessionExercise>[
      SessionExercise(
        id: 'e-$name',
        name: 'Barbell Bench Press',
        orderIndex: 0,
        sets: <SessionSet>[
          for (var i = 0; i < sets; i++)
            SessionSet(
              id: 's-$name-$i',
              setNumber: i + 1,
              reps: 5,
              weightKg: 80,
              isCompleted: true,
            ),
        ],
      ),
    ],
  );

  // Upper on Monday and Thursday, Lower on Tuesday and Friday.
  StandingPlan plan() => const StandingPlan(
    id: 'p',
    name: 'Upper / Lower',
    dayOrder: <String>['Upper', 'Lower', 'Upper', 'Lower'],
    weekdays: <int>[
      DateTime.monday,
      DateTime.tuesday,
      DateTime.thursday,
      DateTime.friday,
    ],
    slots: <String, List<MovementSlot>>{
      'Upper': <MovementSlot>[
        MovementSlot(
          id: 'a',
          role: 'horizontal press',
          movement: 'Barbell Bench Press',
          sets: 4,
          reps: 6,
          lastTopKg: 85,
          lastTopReps: 6,
        ),
        MovementSlot(
          id: 'b',
          role: 'vertical pull',
          movement: 'Lat Pulldown',
          sets: 3,
          reps: 10,
        ),
      ],
      'Lower': <MovementSlot>[
        MovementSlot(
          id: 'c',
          role: 'squat',
          movement: 'Barbell Back Squat',
          sets: 4,
          reps: 5,
        ),
      ],
    },
  );

  /// A day of the week strip, by what it says to a screen reader.
  Finder day(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label,
  );

  Future<void> pump(
    WidgetTester tester, {
    DateTime? today,
    List<Session> log = const <Session>[],
    Session? openSession,
    StandingPlan? plan,
    String? movedDay,
    VoidCallback? onStartSession,
    VoidCallback? onOpenLibrary,
    ValueChanged<String>? onStartPlanned,
    ValueChanged<Session>? onOpenSession,
    VoidCallback? onOpenPlan,
  }) async {
    // A phone, so every card is on screen and tappable.
    tester.view.physicalSize = const Size(430 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackSurface(
            today: today ?? now,
            log: log,
            openSession: openSession,
            plan: plan,
            movedDay: movedDay,
            onStartSession: onStartSession,
            onOpenLibrary: onOpenLibrary,
            onStartPlanned: onStartPlanned,
            onOpenSession: onOpenSession,
            onOpenPlan: onOpenPlan,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the header', () {
    testWidgets('the app, a greeting, and the date on the Today card', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('LIFT'), findsOneWidget);
      expect(find.text('Evening'), findsOneWidget);
      expect(find.text('TODAY · THURSDAY 1 OCT'), findsOneWidget);
    });

    testWidgets('the greeting follows the clock', (tester) async {
      await pump(tester, today: DateTime(2026, 10, 1, 7));
      expect(find.text('Morning'), findsOneWidget);
    });
  });

  group('Today, with no plan', () {
    testWidgets('nothing logged ever: ready, and Start a session', (
      tester,
    ) async {
      await pump(tester, onOpenLibrary: () {});
      expect(find.text('Ready when you are'), findsOneWidget);
      expect(find.text('Start a session'), findsOneWidget);
    });

    testWidgets('Start a session opens the workouts, not a blank session', (
      tester,
    ) async {
      var library = 0;
      var blank = 0;
      await pump(
        tester,
        log: <Session>[finished('Push', DateTime(2026, 9, 29, 18))],
        onOpenLibrary: () => library++,
        onStartSession: () => blank++,
      );
      expect(find.text('No session yet today'), findsOneWidget);
      expect(find.text('Pick a workout, or start blank.'), findsOneWidget);

      await tester.tap(find.text('Start a session'));
      expect(library, 1);
      expect(blank, 0);
    });

    testWidgets('with no library, it starts a blank one', (tester) async {
      var blank = 0;
      await pump(
        tester,
        log: <Session>[finished('Push', DateTime(2026, 9, 29, 18))],
        onStartSession: () => blank++,
      );
      expect(find.text('Add movements as you go.'), findsOneWidget);
      await tester.tap(find.text('Start a session'));
      expect(blank, 1);
    });

    testWidgets('trained today: the session, and Start another', (
      tester,
    ) async {
      await pump(
        tester,
        log: <Session>[
          finished('Push', DateTime(2026, 10, 1, 7), minutes: 62, sets: 7),
        ],
        onOpenLibrary: () {},
      );
      expect(find.text('Push'), findsOneWidget);
      expect(find.text('Done at 8:02am · 1h 02m · 7 sets'), findsOneWidget);
      expect(find.text('Start another session'), findsOneWidget);
      // The card above is already showing it.
      expect(find.text('LAST SESSION'), findsNothing);
    });
  });

  group('Today, with a plan', () {
    testWidgets('a training day: its name, a count, and its own button', (
      tester,
    ) async {
      String? started;
      await pump(
        tester,
        plan: plan(),
        onStartPlanned: (day) => started = day,
        onOpenLibrary: () {},
      );
      expect(find.text('Upper'), findsOneWidget);
      // A count only (TR5): the movements are inside the session.
      expect(find.text('2 movements'), findsOneWidget);
      expect(find.text('Barbell Bench Press'), findsNothing);

      await tester.tap(find.text('Start upper'));
      expect(started, 'Upper');
    });

    testWidgets('Start something else opens the workouts', (tester) async {
      var library = 0;
      await pump(
        tester,
        plan: plan(),
        onStartPlanned: (_) {},
        onOpenLibrary: () => library++,
      );
      await tester.tap(find.text('Start something else'));
      expect(library, 1);
    });

    testWidgets('a day brought forward says where it came from', (
      tester,
    ) async {
      await pump(
        tester,
        // A Wednesday, which the plan rests on.
        today: DateTime(2026, 9, 30, 18),
        plan: plan(),
        movedDay: 'Lower',
        onStartPlanned: (_) {},
      );
      expect(find.text('Lower'), findsOneWidget);
      expect(find.text('1 movement · moved from Tuesday'), findsOneWidget);
    });

    testWidgets('a rest day: what is next, and no start pushed', (
      tester,
    ) async {
      var library = 0;
      await pump(
        tester,
        today: DateTime(2026, 9, 30, 18),
        plan: plan(),
        onStartPlanned: (_) {},
        onOpenLibrary: () => library++,
      );
      expect(find.text('Rest day'), findsOneWidget);
      expect(find.text('Next: Upper on Thursday.'), findsOneWidget);
      expect(find.text('Start a session'), findsNothing);
      // Said once: the week card leaves it to the card above.
      expect(find.textContaining('Next · '), findsNothing);

      await tester.tap(find.text('Start a session anyway'));
      expect(library, 1);
    });

    testWidgets('done already: it does not offer the same day again', (
      tester,
    ) async {
      await pump(
        tester,
        plan: plan(),
        log: <Session>[finished('Upper', DateTime(2026, 10, 1, 17))],
        onStartPlanned: (_) {},
        onOpenLibrary: () {},
      );
      expect(find.text('Start upper'), findsNothing);
      expect(find.text('Start another session'), findsOneWidget);
    });
  });

  group('Today, with a session open', () {
    Session open(DateTime startedAt) => Session(
      id: 'open',
      name: 'Push',
      startedAt: startedAt,
      exercises: const <SessionExercise>[
        SessionExercise(
          id: 'e',
          name: 'Barbell Bench Press',
          orderIndex: 0,
          sets: <SessionSet>[
            SessionSet(id: 's1', setNumber: 1, isCompleted: true),
            SessionSet(id: 's2', setNumber: 2, isCompleted: true),
            SessionSet(id: 's3', setNumber: 3),
          ],
        ),
      ],
    );

    testWidgets('says what it is and how far in, and resumes', (tester) async {
      var resumed = 0;
      var library = 0;
      await pump(
        tester,
        openSession: open(DateTime(2026, 10, 1, 17, 56)),
        onStartSession: () => resumed++,
        onOpenLibrary: () => library++,
      );
      expect(find.text('Push'), findsOneWidget);
      expect(
        find.text('2 sets in · 1 movement · started 5:56pm'),
        findsOneWidget,
      );

      // Resuming beats starting, plan or no plan.
      expect(find.text('Start a session'), findsNothing);
      await tester.tap(find.text('Resume session'));
      expect(resumed, 1);
      expect(library, 0);
    });

    testWidgets('left open on another day, it says so', (tester) async {
      await pump(
        tester,
        openSession: open(DateTime(2026, 9, 30, 19)),
        onStartSession: () {},
      );
      expect(
        find.text('Left open yesterday · 2 sets in · 1 movement'),
        findsOneWidget,
      );
      expect(find.text('Resume session'), findsOneWidget);
    });

    testWidgets('it beats a planned day', (tester) async {
      await pump(
        tester,
        plan: plan(),
        openSession: open(DateTime(2026, 10, 1, 17, 56)),
        onStartSession: () {},
        onStartPlanned: (_) {},
      );
      expect(find.text('Start upper'), findsNothing);
      expect(find.text('Resume session'), findsOneWidget);
    });
  });

  group('This week', () {
    testWidgets('counts sessions and time since Monday, not volume', (
      tester,
    ) async {
      await pump(
        tester,
        log: <Session>[
          // Monday and Wednesday of this week, and one from the week before.
          finished('Pull', DateTime(2026, 9, 28, 18, 30), minutes: 54),
          finished('Push', DateTime(2026, 9, 30, 7, 15), minutes: 62),
          finished('Legs', DateTime(2026, 9, 26, 10), minutes: 90),
        ],
      );
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('SESSIONS'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('1h 56m'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);

      // When, on the day it happened.
      expect(find.text('6:30pm'), findsOneWidget);
      expect(find.text('7:15am'), findsOneWidget);
      expect(day('Monday, trained at 6:30pm'), findsOneWidget);
      expect(day('Thursday, today'), findsOneWidget);
    });

    testWidgets('a phone on the 24-hour clock reads 18:30', (tester) async {
      tester.view.physicalSize = const Size(430 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
          home: Scaffold(
            body: TrackSurface(
              today: now,
              log: <Session>[finished('Pull', DateTime(2026, 9, 28, 18, 30))],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('18:30'), findsOneWidget);
      expect(find.text('Mon 28 Sep, 18:30'), findsOneWidget);
    });

    testWidgets('two sessions in a day are said as two', (tester) async {
      await pump(
        tester,
        log: <Session>[
          finished('Push', DateTime(2026, 9, 29, 7)),
          finished('Pull', DateTime(2026, 9, 29, 18)),
        ],
      );
      expect(day('Tuesday, 2 sessions, the first at 7:00am'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('an empty week shows dashes rather than zeroes', (
      tester,
    ) async {
      // A nought on day one reads as a scoreboard somebody is already losing.
      await pump(tester);
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('0'), findsNothing);
    });

    testWidgets('with a plan: of how many, what is next, and the way to it', (
      tester,
    ) async {
      var opened = 0;
      await pump(
        tester,
        plan: plan(),
        log: <Session>[finished('Upper', DateTime(2026, 9, 28, 18))],
        onStartPlanned: (_) {},
        onOpenPlan: () => opened++,
      );
      expect(find.text('1 of 4'), findsOneWidget);
      expect(find.text('Next · Lower on Friday'), findsOneWidget);
      expect(day('Tuesday, planned'), findsOneWidget);

      await tester.tap(find.text('THIS WEEK'));
      expect(opened, 1);
    });

    testWidgets('without a plan it goes nowhere', (tester) async {
      var opened = 0;
      await pump(
        tester,
        log: <Session>[finished('Push', DateTime(2026, 9, 28, 18))],
        onOpenPlan: () => opened++,
      );
      await tester.tap(find.text('THIS WEEK'));
      expect(opened, 0);
    });
  });

  group('Last session', () {
    testWidgets('its name, when, how long, and no volume', (tester) async {
      Session? opened;
      final push = finished(
        'Push',
        DateTime(2026, 9, 30, 18, 30),
        minutes: 62,
        sets: 7,
      );
      await pump(
        tester,
        log: <Session>[finished('Pull', DateTime(2026, 9, 28, 18)), push],
        onOpenSession: (s) => opened = s,
      );
      expect(find.text('LAST SESSION'), findsOneWidget);
      expect(find.text('Push'), findsOneWidget);
      expect(find.text('Wed 30 Sep, 6:30pm'), findsOneWidget);
      expect(find.text('1h 02m'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('LENGTH'), findsOneWidget);
      expect(find.text('MOVEMENTS'), findsOneWidget);
      expect(find.text('VOLUME'), findsNothing);

      await tester.tap(find.text('Push'));
      expect(opened, push);
    });

    testWidgets('before there is one, says what will be here', (tester) async {
      await pump(tester);
      expect(
        find.text('Your latest session lands here, with how long it took.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the saved workouts are not on Track any more (TR3)', (
    tester,
  ) async {
    await pump(tester, onOpenLibrary: () {});
    expect(find.text('YOUR WORKOUTS'), findsNothing);
    expect(find.text('START FROM ONE OF THESE'), findsNothing);
    expect(find.text('See all'), findsNothing);
  });

  group('in the shell', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.memory());
    tearDown(() async => db.close());

    Future<void> pumpShell(
      WidgetTester tester,
      InMemoryWorkoutLibrary library,
    ) async {
      tester.view.physicalSize = const Size(430 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
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
    }

    testWidgets('Start a session, then a saved workout: two taps', (
      tester,
    ) async {
      final library = InMemoryWorkoutLibrary();
      await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[
          TemplateMovement('Barbell Bench Press'),
          TemplateMovement('Cable Fly'),
        ],
      );
      await pumpShell(tester, library);

      await tester.tap(find.text('Start a session'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutLibraryScreen), findsOneWidget);
      expect(find.text('Blank session'), findsOneWidget);

      await tester.tap(find.text('Start').last);
      await tester.pumpAndSettle();
      expect(find.byType(ActiveSessionScreen), findsOneWidget);
      expect(find.text('Cable Fly'), findsOneWidget);
    });

    testWidgets('Start a session, then Blank session: an empty one', (
      tester,
    ) async {
      await pumpShell(tester, InMemoryWorkoutLibrary());

      await tester.tap(find.text('Start a session'));
      await tester.pumpAndSettle();
      // Nothing saved, so the three starters are under the blank row.
      expect(find.text('Full Body'), findsOneWidget);

      await tester.tap(find.text('Blank session'));
      await tester.pumpAndSettle();
      expect(find.byType(ActiveSessionScreen), findsOneWidget);
      expect(find.text('Add exercise'), findsOneWidget);

      // And backing out leaves Track offering it back.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Resume session'), findsOneWidget);
    });
  });
}
