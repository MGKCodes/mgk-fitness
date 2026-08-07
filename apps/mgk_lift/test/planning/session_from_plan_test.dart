import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/plan.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_validator.dart';
import 'package:mgk_lift/src/features/planning/domain/session_from_plan.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/domain/session_recorder.dart';
import 'package:mgk_units/mgk_units.dart';

/// A recorder that keeps a session in memory, so filling one from a plan can be
/// asserted without a database.
class FakeRecorder implements SessionRecorder {
  Session? _session;
  int _ids = 0;

  String get _nextId => 'id${++_ids}';

  @override
  Future<Session?> current() async => _session;

  @override
  Future<Session> start({String? name, DateTime? at}) async =>
      _session = Session(
        id: 'session',
        name: name ?? 'Session',
        startedAt: at ?? DateTime(2026, 8, 10),
      );

  @override
  Future<Session> addExercise(String name, {String? cardioMode}) async {
    final s = _session!;
    // Seeds one set, exactly as the real recorder does.
    return _session = _copy(s, <SessionExercise>[
      ...s.exercises,
      SessionExercise(
        id: _nextId,
        name: name,
        orderIndex: s.exercises.length,
        sets: <SessionSet>[SessionSet(id: _nextId, setNumber: 1)],
      ),
    ]);
  }

  @override
  Future<Session> addSet(String exerciseId) async {
    final s = _session!;
    return _session = _copy(s, <SessionExercise>[
      for (final e in s.exercises)
        if (e.id == exerciseId)
          _copyExercise(e, <SessionSet>[
            ...e.sets,
            SessionSet(id: _nextId, setNumber: e.sets.length + 1),
          ])
        else
          e,
    ]);
  }

  @override
  Future<Session> updateSet(
    String setId, {
    int? reps,
    double? weightKg,
    bool? isCompleted,
    SetType? setType,
    int? durationS,
    double? distanceM,
  }) async {
    final s = _session!;
    return _session = _copy(s, <SessionExercise>[
      for (final e in s.exercises)
        _copyExercise(e, <SessionSet>[
          for (final set in e.sets)
            if (set.id == setId)
              SessionSet(
                id: set.id,
                setNumber: set.setNumber,
                reps: reps ?? set.reps,
                weightKg: weightKg ?? set.weightKg,
                isCompleted: isCompleted ?? set.isCompleted,
                setType: setType ?? set.setType,
              )
            else
              set,
        ]),
    ]);
  }

  @override
  Future<Session> removeSet(String setId) async => _session!;

  @override
  Future<Session> removeExercise(String exerciseId) async {
    final s = _session!;
    return _session = _copy(s, <SessionExercise>[
      for (final e in s.exercises)
        if (e.id != exerciseId) e,
    ]);
  }

  @override
  Future<Session> finish({DateTime? at}) async => _session!;

  @override
  Future<void> discard() async => _session = null;

  static Session _copy(Session s, List<SessionExercise> exercises) => Session(
    id: s.id,
    name: s.name,
    startedAt: s.startedAt,
    endedAt: s.endedAt,
    notes: s.notes,
    exercises: exercises,
  );

  static SessionExercise _copyExercise(
    SessionExercise e,
    List<SessionSet> sets,
  ) => SessionExercise(
    id: e.id,
    name: e.name,
    orderIndex: e.orderIndex,
    notes: e.notes,
    cardioMode: e.cardioMode,
    sets: sets,
  );
}

PlanSession planned(List<PlannedMovement> movements) => PlanSession(
  id: 'p1-w1-d1',
  weekNumber: 1,
  weekday: 1,
  scheduledDate: DateTime(2026, 8, 10),
  kind: 'push',
  movements: movements,
);

void main() {
  group('starting a planned session', () {
    test('the movements and their numbers are already in', () async {
      // The whole difference between a plan and a template. The weight is here
      // because the coach derived it from this lifter's own log, not because
      // the app decided something only they could know.
      final recorder = FakeRecorder();
      final session = await SessionFromPlan(recorder).start(
        planned(<PlannedMovement>[
          PlannedMovement(
            name: 'Barbell Bench Press',
            sets: 3,
            reps: 5,
            target: const Mass.kilograms(85),
          ),
        ]),
      );

      final exercise = session.exercises.single;
      expect(exercise.name, 'Barbell Bench Press');
      expect(exercise.sets, hasLength(3));
      for (final set in exercise.sets) {
        expect(set.reps, 5);
        expect(set.weightKg, 85);
      }
    });

    test('a movement with no target is left blank, not zeroed', () async {
      // "3x8, leave two in the tank" is a real prescription. A 0 kg in the
      // field would read as a bug and would have to be cleared before logging.
      final recorder = FakeRecorder();
      final session = await SessionFromPlan(recorder).start(
        planned(const <PlannedMovement>[
          PlannedMovement(name: 'Cable Fly', sets: 3, reps: 12),
        ]),
      );

      for (final set in session.exercises.single.sets) {
        expect(set.reps, 12);
        expect(set.weightKg, 0, reason: 'blank, and never a made-up number');
      }
    });

    test('nothing is ticked off — they still have to do it', () async {
      // The one thing a tracker must never do is log a session nobody did.
      final recorder = FakeRecorder();
      final session = await SessionFromPlan(recorder).start(
        planned(<PlannedMovement>[
          PlannedMovement(
            name: 'Barbell Bench Press',
            sets: 3,
            reps: 5,
            target: const Mass.kilograms(85),
          ),
        ]),
      );
      expect(
        session.exercises.single.sets.every((SessionSet s) => !s.isCompleted),
        isTrue,
      );
    });

    test('the session is named after what the plan called it', () async {
      final recorder = FakeRecorder();
      final session = await SessionFromPlan(recorder).start(
        planned(const <PlannedMovement>[
          PlannedMovement(name: 'Cable Fly', sets: 1, reps: 10),
        ]),
      );
      expect(session.name, 'Push');
    });
  });

  group('applying a swap to the plan', () {
    const bench = PlannedMovement(
      name: 'Barbell Bench Press',
      sets: 3,
      reps: 5,
    );
    const fly = PlannedMovement(name: 'Cable Fly', sets: 3, reps: 12);
    const dumbbell = PlannedMovement(
      name: 'Dumbbell Bench Press',
      sets: 3,
      reps: 8,
    );

    test('the right movement is replaced and the rest are untouched', () {
      final after = applySwap(
        const <PlannedMovement>[bench, fly],
        replaces: 'Barbell Bench Press',
        with_: dumbbell,
      );
      expect(after.map((m) => m.name), <String>[
        'Dumbbell Bench Press',
        'Cable Fly',
      ]);
    });

    test('names match loosely, because they round-trip through a model', () {
      // The coach is told the name and hands it back, and that is not
      // case-preserving. Matching strictly would silently replace nothing.
      final after = applySwap(
        const <PlannedMovement>[bench, fly],
        replaces: '  barbell bench press ',
        with_: dumbbell,
      );
      expect(after.first.name, 'Dumbbell Bench Press');
    });

    test('a movement that is not there changes nothing', () {
      final after = applySwap(
        const <PlannedMovement>[bench, fly],
        replaces: 'Barbell Squat',
        with_: dumbbell,
      );
      expect(after.map((m) => m.name), <String>[
        'Barbell Bench Press',
        'Cable Fly',
      ]);
    });
  });
}
