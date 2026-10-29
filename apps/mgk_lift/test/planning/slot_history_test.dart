import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/planning/domain/session_prescription.dart';
import 'package:mgk_lift/src/features/planning/domain/slot_history.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan_store.dart';
import 'package:mgk_lift/src/features/stats/data/drift_session_history.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/presentation/active_session_screen.dart';

const String bench = 'Barbell Bench Press';

var _ids = 0;

SessionSet _set(
  double kg,
  int reps, {
  bool warmup = false,
  bool ticked = true,
}) => SessionSet(
  id: 's${_ids++}',
  setNumber: 1,
  weightKg: kg,
  reps: reps,
  isCompleted: ticked,
  setType: warmup ? SetType.warmup : SetType.working,
);

Session _session(
  DateTime day,
  List<SessionSet> sets, {
  String movement = bench,
  bool inProgress = false,
}) => Session(
  id: 'w${_ids++}',
  name: 'Upper',
  startedAt: day,
  endedAt: inProgress ? null : day.add(const Duration(hours: 1)),
  exercises: <SessionExercise>[
    SessionExercise(
      id: 'e${_ids++}',
      name: movement,
      orderIndex: 0,
      sets: <SessionSet>[
        for (var i = 0; i < sets.length; i++) sets[i].numbered(i + 1),
      ],
    ),
  ],
);

/// One session a week of [movement], oldest first, each at its top set.
List<Session> _weeks(List<(double, int)> tops, {String movement = bench}) =>
    <Session>[
      for (var i = 0; i < tops.length; i++)
        _session(DateTime(2026, 9, 7 + i * 7, 18), <SessionSet>[
          _set(tops[i].$1, tops[i].$2),
        ], movement: movement),
    ];

const MovementSlot benchSlot = MovementSlot(
  id: 'a',
  role: 'horizontal press',
  movement: bench,
  isMain: true,
  sets: 3,
  reps: 5,
);

const MovementSlot pulldownSlot = MovementSlot(
  id: 'b',
  role: 'vertical pull',
  movement: 'Lat Pulldown',
  sets: 3,
  reps: 10,
);

/// Upper on Mondays: the bench, done before, and a pulldown that never was.
const StandingPlan upper = StandingPlan(
  id: 'p',
  name: 'Upper',
  dayOrder: <String>['Upper'],
  weekdays: <int>[DateTime.monday],
  slots: <String, List<MovementSlot>>{
    'Upper': <MovementSlot>[benchSlot, pulldownSlot],
  },
);

void main() {
  group('a slot\'s history, read off the log', () {
    test('a movement never done has none', () {
      expect(SlotHistory.of(const <Session>[], bench), isNull);
      expect(
        SlotHistory.of(
          _weeks(<(double, int)>[(60, 10)], movement: 'Row'),
          bench,
        ),
        isNull,
      );
    });

    test('done once: that session\'s top set, and it counts as moved', () {
      // They picked a weight they could do comfortably, so the first increment
      // is the next step rather than a second session at the same weight.
      final h = SlotHistory.of(<Session>[
        _session(DateTime(2026, 9, 7), <SessionSet>[
          _set(80, 8),
          _set(85, 6),
          _set(90, 5),
        ]),
      ], bench)!;
      expect(h.top.weight.kilograms, 90);
      expect(h.top.reps, 5);
      expect(h.sessionsAtSameTop, 0);
    });

    test('heavier than last time is moved', () {
      final h = SlotHistory.of(
        _weeks(<(double, int)>[(80, 5), (82.5, 5)]),
        bench,
      )!;
      expect(h.top.weight.kilograms, 82.5);
      expect(h.sessionsAtSameTop, 0);
    });

    test('as heavy for more reps is moved (ADR 0004)', () {
      final h = SlotHistory.of(
        _weeks(<(double, int)>[(80, 5), (80, 6)]),
        bench,
      )!;
      expect(h.top.reps, 6);
      expect(h.sessionsAtSameTop, 0);
    });

    test('heavier for fewer reps is moved: weight first, as for a best', () {
      final h = SlotHistory.of(
        _weeks(<(double, int)>[(80, 8), (85, 3)]),
        bench,
      )!;
      expect(h.top.weight.kilograms, 85);
      expect(h.sessionsAtSameTop, 0);
    });

    test('the same top set again is held, and holds count up', () {
      final h = SlotHistory.of(
        _weeks(<(double, int)>[(80, 5), (80, 5), (80, 5)]),
        bench,
      )!;
      expect(h.sessionsAtSameTop, 2);
    });

    test('lighter is held, not a regression, and is what last time was', () {
      // A light day is a light day. It counts toward a stall like any other
      // session that did not move, and "last time" is still last time.
      final h = SlotHistory.of(
        _weeks(<(double, int)>[(85, 5), (80, 5)]),
        bench,
      )!;
      expect(h.top.weight.kilograms, 80);
      expect(h.sessionsAtSameTop, 1);
    });

    test('the count starts after the last time it moved', () {
      // Out of order on purpose: the log is not promised sorted.
      final log = _weeks(<(double, int)>[(75, 5), (80, 5), (80, 5), (80, 5)]);
      final h = SlotHistory.of(log.reversed.toList(), bench)!;
      expect(h.top.weight.kilograms, 80);
      expect(h.sessionsAtSameTop, 2);
    });

    test('a warm-up is never the top set', () {
      final h = SlotHistory.of(<Session>[
        _session(DateTime(2026, 9, 7), <SessionSet>[
          _set(100, 1, warmup: true),
          _set(80, 5),
        ]),
      ], bench)!;
      expect(h.top.weight.kilograms, 80);
    });

    test('a session of warm-ups only is not a session of it', () {
      // Otherwise it would read as a lighter session and count as a hold.
      final log = <Session>[
        ..._weeks(<(double, int)>[(80, 5)]),
        _session(DateTime(2026, 9, 20), <SessionSet>[
          _set(60, 5, warmup: true),
        ]),
      ];
      final h = SlotHistory.of(log, bench)!;
      expect(h.top.weight.kilograms, 80);
      expect(h.sessionsAtSameTop, 0);
    });

    test('unticked sets and a session still open do not count', () {
      final h = SlotHistory.of(<Session>[
        _session(DateTime(2026, 9, 7), <SessionSet>[
          _set(80, 5),
          _set(90, 5, ticked: false),
        ]),
        _session(DateTime(2026, 9, 14), <SessionSet>[
          _set(85, 5),
        ], inProgress: true),
      ], bench)!;
      expect(h.top.weight.kilograms, 80);
      expect(h.sessionsAtSameTop, 0);
    });

    test('names match whatever their case', () {
      final h = SlotHistory.of(
        _weeks(<(double, int)>[(80, 5)], movement: 'barbell BENCH press'),
        bench,
      );
      expect(h?.top.weight.kilograms, 80);
    });

    test('bodyweight work has no top set to give', () {
      // No weight to have gone past (ADR 0004), so the slot keeps its advice.
      expect(SlotHistory.of(_weeks(<(double, int)>[(0, 12)]), bench), isNull);
    });
  });

  test('a swap mid-session leaves the slot its own history', () {
    // Bench on the 7th, then the rack was busy on the 14th and it was swapped
    // for dumbbells. The dumbbell press has a history of its own now; the
    // bench's is still the 7th's, and the plan still says bench.
    final log = <Session>[
      ..._weeks(<(double, int)>[(80, 5)]),
      _session(DateTime(2026, 9, 14), <SessionSet>[
        _set(30, 10),
      ], movement: 'Dumbbell Bench Press'),
    ];

    final slot = slotWithHistory(benchSlot, log);
    expect(slot.movement, bench);
    expect(slot.lastTopKg, 80);
    expect(slot.sessionsAtSameTop, 0);
    expect(SlotHistory.of(log, 'Dumbbell Bench Press')?.top.reps, 10);
  });

  group('the plan, with its history', () {
    test('each slot gets its movement\'s, and one never done gets none', () {
      final plan = planWithHistory(upper, _weeks(<(double, int)>[(80, 5)]));
      final slots = plan.slots['Upper']!;
      expect(slots[0].lastTopKg, 80);
      expect(slots[0].lastTopReps, 5);
      expect(slots[1].hasHistory, isFalse);
      // Everything else about the plan is untouched.
      expect(plan.id, upper.id);
      expect(slots.map((s) => s.sets), <int>[3, 3]);
      expect(slots.map((s) => s.reps), <int>[5, 10]);
    });

    test('the log is the only source: history a slot came with is dropped', () {
      const stale = MovementSlot(
        id: 'a',
        role: 'horizontal press',
        movement: bench,
        sets: 3,
        reps: 5,
        lastTopKg: 200,
        lastTopReps: 1,
        sessionsAtSameTop: 9,
      );
      final slot = slotWithHistory(stale, const <Session>[]);
      expect(slot.hasHistory, isFalse);
      expect(slot.sessionsAtSameTop, 0);
    });

    test('a planned session prescribes from it: on one, and held', () {
      final moved = SessionPrescription.forDay(
        planWithHistory(
          upper,
          _weeks(<(double, int)>[(80, 5)]),
        ).slots['Upper']!,
      );
      expect(moved[0].target?.kilograms, 82.5);
      expect(moved[0].note, isNull);
      // Never done: no number, and the advice instead.
      expect(moved[1].target, isNull);
      expect(moved[1].note, contains('comfortably'));

      final held = SessionPrescription.forDay(
        planWithHistory(
          upper,
          _weeks(<(double, int)>[(80, 5), (80, 5)]),
        ).slots['Upper']!,
      );
      expect(held[0].target?.kilograms, 80);
    });

    test(
      'an accessory held for six sessions goes stale; a main lift never',
      () {
        const raise = MovementSlot(
          id: 'c',
          role: 'lateral raise',
          movement: 'Dumbbell Lateral Raise',
          sets: 3,
          reps: 12,
        );
        const plan = StandingPlan(
          id: 'p',
          name: 'Upper',
          dayOrder: <String>['Upper'],
          weekdays: <int>[DateTime.monday],
          slots: <String, List<MovementSlot>>{
            'Upper': <MovementSlot>[benchSlot, raise],
          },
        );
        final log = <Session>[
          ..._weeks(
            List<(double, int)>.filled(7, (12, 12)),
            movement: raise.movement,
          ),
          ..._weeks(List<(double, int)>.filled(7, (80, 5))),
        ];

        final lifted = planWithHistory(plan, log);
        expect(lifted.stalled.map((s) => s.role), <String>['lateral raise']);
        final day = SessionPrescription.forDay(lifted.slots['Upper']!);
        expect(day[1].note, 'Not moved in 6 sessions');
        // A stalled squat is a programming problem, not a swap (standing_plan).
        expect(lifted.slots['Upper']![0].sessionsAtSameTop, 6);
        expect(day[0].target?.kilograms, 80);
      },
    );
  });

  group('in the shell', () {
    late AppDatabase db;
    late DriftSessionRecorder recorder;

    setUp(() {
      db = AppDatabase.memory();
      var n = 0;
      recorder = DriftSessionRecorder(db, idFactory: () => 'r-${++n}');
    });
    tearDown(() async => db.close());

    // A Monday, which the plan trains Upper on.
    final monday = DateTime(2026, 10, 26, 18);

    /// Last Thursday's bench, logged the ordinary way: 80 kg for 5, ticked.
    Future<void> logBench() async {
      await recorder.start(name: 'Push', at: DateTime(2026, 10, 22, 18));
      final added = await recorder.addExercise(bench);
      final s = await recorder.addSet(
        added.exercises.single.id,
        reps: 5,
        weightKg: 80,
      );
      await recorder.updateSet(
        s.exercises.single.sets.single.id,
        isCompleted: true,
      );
      await recorder.finish(at: DateTime(2026, 10, 22, 19));
    }

    Future<void> pumpShell(WidgetTester tester, {int tab = 0}) async {
      tester.view.physicalSize = const Size(430 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: LiftShell(
            recorder: recorder,
            history: DriftSessionHistory(db),
            plans: InMemoryStandingPlanStore(upper),
            isEntitled: true,
            today: monday,
            initialTab: tab,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Plan says what was lifted last time, from the log', (
      tester,
    ) async {
      await logBench();
      await pumpShell(tester, tab: 1);

      expect(find.text('last time 80 kg × 5'), findsOneWidget);
      expect(find.text('first time'), findsOneWidget);
    });

    testWidgets('the planned session after it opens on the next weight', (
      tester,
    ) async {
      // #4: every planned session opened blank, because nothing ever gave a
      // slot a history to prescribe from.
      await logBench();
      await pumpShell(tester);

      await tester.tap(find.text('Start upper'));
      await tester.pumpAndSettle();
      expect(find.byType(ActiveSessionScreen), findsOneWidget);

      final open = (await recorder.current())!;
      final benched = open.exercises.firstWhere((e) => e.name == bench);
      expect(benched.sets, hasLength(3));
      for (final set in benched.sets) {
        expect(set.weightKg, 82.5);
        expect(set.reps, 5);
        expect(set.isCompleted, isFalse, reason: 'prefilled, not logged');
      }
      // Never done, so no number put in for them.
      final pulldown = open.exercises.firstWhere(
        (e) => e.name == 'Lat Pulldown',
      );
      expect(pulldown.sets.every((s) => s.weightKg == 0), isTrue);
    });
  });
}
