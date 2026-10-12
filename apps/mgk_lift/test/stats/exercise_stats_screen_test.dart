import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/stats/domain/movement_history.dart';
import 'package:mgk_lift/src/features/stats/presentation/exercise_stats_screen.dart';
import 'package:mgk_lift/src/features/tracking/data/exercise_lookup.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/presentation/exercise_thumb.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

const _bench = 'Barbell Bench Press';

Session session(
  DateTime day, {
  String name = 'Evening session',
  String exercise = _bench,
  List<SessionSet> sets = const <SessionSet>[],
  bool finished = true,
}) => Session(
  id: day.toIso8601String() + exercise,
  name: name,
  startedAt: day,
  endedAt: finished ? day.add(const Duration(hours: 1)) : null,
  exercises: <SessionExercise>[
    SessionExercise(
      id: 'e$exercise',
      name: exercise,
      orderIndex: 0,
      sets: sets,
    ),
  ],
);

SessionSet done(double kg, int reps, {SetType type = SetType.working}) =>
    SessionSet(
      id: 's$kg-$reps-$type',
      setNumber: 1,
      weightKg: kg,
      reps: reps,
      isCompleted: true,
      setType: type,
    );

/// A movement's stats screen (R9). The personal-best rules moved here from
/// Profile's list of bests, and their tests with them.
void main() {
  final now = DateTime(2026, 8, 30);

  Future<void> show(
    WidgetTester tester,
    List<Session> log, {
    String name = _bench,
    bool catalogued = true,
    MassUnit unit = MassUnit.kilograms,
    ValueChanged<Session>? onOpenSession,
  }) async {
    tester.view
      ..physicalSize = const Size(1179, 6000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ExerciseStatsScreen(
          name: name,
          log: log,
          catalogue: catalogued ? ExerciseLookup().find(name) : null,
          massUnit: unit,
          now: now,
          onOpenSession: onOpenSession,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('working weights (#3)', () {
    // No one-rep max on show: it read as a best nobody had lifted. The
    // estimate is turned into what to load instead.

    testWidgets('one per rep range, from the set behind them', (tester) async {
      await show(tester, <Session>[
        session(DateTime(2026, 8, 3), sets: <SessionSet>[done(120, 6)]),
      ]);

      expect(find.text('WORKING WEIGHTS'), findsOneWidget);
      // Epley's 144 kg, a rep in reserve, down to the barbell's 2.5 kg.
      expect(find.text('4–6 reps'), findsOneWidget);
      expect(find.text('115–122.5 kg'), findsOneWidget);
      expect(find.text('102.5–112.5 kg'), findsOneWidget);
      // The range Epley is least sure of says so.
      expect(find.text('~90–100 kg'), findsOneWidget);
      expect(find.textContaining('120 kg × 6 on 3 Aug'), findsOneWidget);
      expect(find.text('EST. 1RM'), findsNothing);
      expect(find.text('144 kg'), findsNothing);
    });

    testWidgets('dumbbells step by 2 kg', (tester) async {
      await show(tester, name: 'Dumbbell Bench Press', <Session>[
        session(
          DateTime(2026, 8, 3),
          exercise: 'Dumbbell Bench Press',
          sets: <SessionSet>[done(30, 8)],
        ),
      ]);

      // 38 kg estimated: 30.8 and 32.6 for 4–6, down to a pair that exists.
      expect(find.text('30–32 kg'), findsOneWidget);
    });

    testWidgets('in pounds, in pounds steps', (tester) async {
      await show(tester, unit: MassUnit.pounds, <Session>[
        session(
          DateTime(2026, 8, 3),
          sets: <SessionSet>[done(Mass.pounds(225).kilograms, 5)],
        ),
      ]);

      // 262.5 lb estimated. 225 for four is exact, and stays 225 rather than
      // falling a step on a rounding error.
      expect(find.text('210–225 lb'), findsOneWidget);
    });

    testWidgets('nothing in the last six weeks hides them', (tester) async {
      await show(tester, <Session>[
        session(DateTime(2026, 7, 1), sets: <SessionSet>[done(120, 6)]),
      ]);

      expect(find.text('WORKING WEIGHTS'), findsNothing);
      // What happened is all still here.
      expect(find.text('1 Jul · Evening session'), findsOneWidget);
      expect(find.text('120 kg'), findsOneWidget);
    });

    testWidgets('nothing at 12 reps or fewer hides them', (tester) async {
      await show(tester, <Session>[
        session(DateTime(2026, 8, 3), sets: <SessionSet>[done(60, 20)]),
      ]);

      expect(find.text('WORKING WEIGHTS'), findsNothing);
      // The session is still listed: it happened, it just has no estimate.
      expect(find.text('3 Aug · Evening session'), findsOneWidget);
    });

    testWidgets('an unloaded movement has none either', (tester) async {
      await show(tester, name: 'Pull Up', <Session>[
        session(
          DateTime(2026, 8, 3),
          exercise: 'Pull Up',
          sets: <SessionSet>[done(0, 8)],
        ),
      ]);

      expect(find.text('WORKING WEIGHTS'), findsNothing);
      // Its sets are reps, as the summary says them, not "0 kg × 8".
      expect(find.text('8 reps'), findsOneWidget);
      expect(find.textContaining('0 kg'), findsNothing);
    });

    testWidgets('the 12-rep rule is stated, not left to be worked out', (
      tester,
    ) async {
      await show(tester, <Session>[
        session(DateTime(2026, 8, 3), sets: <SessionSet>[done(120, 6)]),
      ]);

      expect(
        find.textContaining('Nothing over 12 reps counts'),
        findsOneWidget,
      );
      expect(find.textContaining('not a tested max'), findsOneWidget);
    });

    testWidgets('a warm-up cannot set it', (tester) async {
      await show(tester, <Session>[
        session(
          DateTime(2026, 8, 3),
          sets: <SessionSet>[
            done(200, 3, type: SetType.warmup),
            done(100, 3),
          ],
        ),
      ]);

      // The heaviest is the working 100, and the bands come from it.
      expect(find.text('100 kg'), findsOneWidget);
      expect(find.text('200 kg'), findsNothing);
      expect(find.text('87.5–92.5 kg'), findsOneWidget);
    });
  });

  group('over time', () {
    testWidgets('one session says the line starts with the next', (
      tester,
    ) async {
      await show(tester, <Session>[
        session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
      ]);

      expect(find.textContaining('The line starts with the next'), findsOne);
    });

    testWidgets('two or more draw a line, and say what it shows', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await show(tester, <Session>[
        session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
        session(DateTime(2026, 8, 10), sets: <SessionSet>[done(105, 5)]),
      ]);

      expect(find.textContaining('The line starts'), findsNothing);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Estimated one-rep max, .* on 3 Aug to .* on 10 Aug'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('recent sessions', () {
    testWidgets('newest first, each with its sets and no estimate', (
      tester,
    ) async {
      await show(tester, <Session>[
        session(
          DateTime(2026, 8, 3),
          name: 'Push',
          sets: <SessionSet>[done(100, 5)],
        ),
        session(
          DateTime(2026, 8, 10),
          name: 'Push again',
          sets: <SessionSet>[done(100, 5), done(105, 3)],
        ),
      ]);

      final older = tester.getTopLeft(find.text('3 Aug · Push')).dy;
      final newer = tester.getTopLeft(find.text('10 Aug · Push again')).dy;
      expect(newer, lessThan(older));
      expect(find.text('100 kg × 5 · 105 kg × 3'), findsOneWidget);
      // Each row's estimate used to sit at its end, unlabelled, reading as a
      // weight lifted that day (#3). The sets are the only weights in a row.
      final row = find.ancestor(
        of: find.text('10 Aug · Push again'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: row.first, matching: find.textContaining('kg')),
        findsOneWidget,
      );
    });

    testWidgets('open the session they came from', (tester) async {
      Session? opened;
      final log = <Session>[
        session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
      ];
      await show(tester, log, onOpenSession: (s) => opened = s);

      await tester.tap(find.text('3 Aug · Evening session'));
      await tester.pumpAndSettle();

      expect(opened, same(log.single));
    });

    testWidgets('a date from another year says the year', (tester) async {
      await show(tester, <Session>[
        session(DateTime(2025, 11, 3), sets: <SessionSet>[done(100, 5)]),
      ]);

      expect(find.text('3 Nov 2025 · Evening session'), findsOneWidget);
    });
  });

  testWidgets('a catalogue movement shows how it is done', (tester) async {
    await show(tester, <Session>[
      session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
    ]);

    expect(find.text('HOW IT IS DONE'), findsOneWidget);
    expect(find.byType(ExerciseThumb), findsNWidgets(2));
  });

  testWidgets('a movement of their own says so, and loses nothing else', (
    tester,
  ) async {
    await show(tester, name: 'Landmine Press', catalogued: false, <Session>[
      session(
        DateTime(2026, 8, 3),
        exercise: 'Landmine Press',
        sets: <SessionSet>[done(40, 8)],
      ),
    ]);

    expect(find.text('Your own movement'), findsOneWidget);
    expect(find.text('HOW IT IS DONE'), findsNothing);
    expect(find.text('3 Aug · Evening session'), findsOneWidget);
  });

  testWidgets('nothing logged says where its history starts', (tester) async {
    await show(tester, const <Session>[]);

    expect(find.textContaining('Nothing logged on this yet'), findsOneWidget);
    expect(find.text('WORKING WEIGHTS'), findsNothing);
  });

  group('the history behind it', () {
    test('ignores a session still in progress, and the case of a name', () {
      final history = MovementHistory.of(<Session>[
        session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
        session(
          DateTime(2026, 8, 4),
          exercise: 'barbell bench press',
          sets: <SessionSet>[done(102.5, 5)],
        ),
        session(
          DateTime(2026, 8, 5),
          sets: <SessionSet>[done(200, 5)],
          finished: false,
        ),
      ], _bench);

      expect(history.sessions, hasLength(2));
      expect(history.heaviest?.weightKg, 102.5);
    });

    test('the line leaves out sessions with no estimate, oldest first', () {
      final history = MovementHistory.of(<Session>[
        session(DateTime(2026, 8, 10), sets: <SessionSet>[done(105, 5)]),
        session(DateTime(2026, 8, 5), sets: <SessionSet>[done(60, 20)]),
        session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
      ], _bench);

      expect(
        <DateTime>[for (final p in history.estimates) p.on],
        <DateTime>[DateTime(2026, 8, 3), DateTime(2026, 8, 10)],
      );
      expect(history.estimates.last.estimate.kilograms, closeTo(122.5, 0.01));
      expect(history.sessions, hasLength(3));
    });

    test('no loaded set means no heaviest', () {
      final history = MovementHistory.of(<Session>[
        session(DateTime(2026, 8, 3), sets: <SessionSet>[done(0, 10)]),
      ], _bench);
      expect(history.heaviest, isNull);
      expect(history.best, isNull);
    });

    test('says the same best Profile used to', () {
      final log = <Session>[
        session(DateTime(2026, 8, 3), sets: <SessionSet>[done(120, 6)]),
      ];
      expect(
        MovementHistory.of(log, _bench).best?.estimate,
        Mass.kilograms(144),
      );
    });
  });
}
