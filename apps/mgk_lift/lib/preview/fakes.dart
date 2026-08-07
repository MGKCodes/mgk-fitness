import '../src/features/stats/domain/session_history.dart';
import '../src/features/planning/domain/plan.dart';
import '../src/features/planning/domain/plan_adaptation.dart';
import '../src/features/planning/domain/plan_generator.dart';
import '../src/features/planning/domain/plan_proposal.dart';
import '../src/features/tracking/domain/session.dart';
import '../src/features/tracking/domain/session_recorder.dart';

/// An in-memory recorder, so the preview needs no database.
///
/// The real one writes to SQLite through `sqlite3_flutter_libs`, which does not
/// exist on web without a WASM build. That is the whole reason this harness
/// exists rather than pointing Playwright at the real app: the screens are what
/// is being reviewed, and standing up a database to look at them would be a
/// dependency on the thing least likely to be wrong.
class FakeSessionRecorder implements SessionRecorder {
  FakeSessionRecorder([this._session]);

  Session? _session;
  int _ids = 0;

  String get _nextId => 'p${++_ids}';

  @override
  Future<Session?> current() async => _session;

  @override
  Future<Session> start({String? name, DateTime? at}) async {
    if (_session != null) throw const SessionInProgress();
    return _session = Session(
      id: 'preview',
      name: name ?? 'Evening session',
      startedAt: at ?? DateTime.now(),
    );
  }

  @override
  Future<Session> addExercise(String name, {String? cardioMode}) async {
    final s = _require();
    return _session = _copy(s, <SessionExercise>[
      ...s.exercises,
      SessionExercise(
        id: _nextId,
        name: name,
        orderIndex: s.exercises.length,
        cardioMode: cardioMode,
      ),
    ]);
  }

  @override
  Future<Session> addSet(String exerciseId) async {
    final s = _require();
    return _session = _copy(s, <SessionExercise>[
      for (final e in s.exercises)
        if (e.id != exerciseId)
          e
        else
          SessionExercise(
            id: e.id,
            name: e.name,
            orderIndex: e.orderIndex,
            cardioMode: e.cardioMode,
            sets: <SessionSet>[
              ...e.sets,
              SessionSet(
                id: _nextId,
                setNumber: e.sets.length + 1,
                reps: e.sets.isEmpty ? 0 : e.sets.last.reps,
                weightKg: e.sets.isEmpty ? 0 : e.sets.last.weightKg,
              ),
            ],
          ),
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
    final s = _require();
    return _session = _copy(s, <SessionExercise>[
      for (final e in s.exercises)
        SessionExercise(
          id: e.id,
          name: e.name,
          orderIndex: e.orderIndex,
          cardioMode: e.cardioMode,
          sets: <SessionSet>[
            for (final set in e.sets)
              if (set.id != setId)
                set
              else
                set.copyWith(
                  reps: reps,
                  weightKg: weightKg,
                  isCompleted: isCompleted,
                  setType: setType,
                  durationS: durationS,
                  distanceM: distanceM,
                ),
          ],
        ),
    ]);
  }

  @override
  Future<Session> removeSet(String setId) async {
    final s = _require();
    return _session = _copy(s, <SessionExercise>[
      for (final e in s.exercises)
        SessionExercise(
          id: e.id,
          name: e.name,
          orderIndex: e.orderIndex,
          cardioMode: e.cardioMode,
          sets: e.sets.where((x) => x.id != setId).toList(),
        ),
    ]);
  }

  @override
  Future<Session> removeExercise(String exerciseId) async {
    final s = _require();
    return _session = _copy(
      s,
      s.exercises.where((e) => e.id != exerciseId).toList(),
    );
  }

  @override
  Future<Session> finish({DateTime? at}) async {
    final s = _require();
    final done = Session(
      id: s.id,
      name: s.name,
      startedAt: s.startedAt,
      endedAt: at ?? DateTime.now(),
      exercises: s.exercises,
    );
    _session = null;
    return done;
  }

  @override
  Future<void> discard() async => _session = null;

  Session _require() {
    final s = _session;
    if (s == null) throw const NoSessionInProgress();
    return s;
  }

  Session _copy(Session s, List<SessionExercise> exercises) => Session(
    id: s.id,
    name: s.name,
    startedAt: s.startedAt,
    endedAt: s.endedAt,
    notes: s.notes,
    exercises: exercises,
  );
}

/// A believable log, so Profile can be reviewed with content in it rather than
/// in its empty state.
///
/// Deliberately not one perfect week: a real log has a gap in it, and a screen
/// that only looks right on tidy data is a screen that has not been reviewed.
List<Session> sampleLog(DateTime now) {
  Session make(
    int daysAgo,
    String name,
    List<(String, List<(double, int)>)> work,
  ) {
    final day = now.subtract(Duration(days: daysAgo));
    var n = 0;
    return Session(
      id: 'log-$daysAgo',
      name: name,
      startedAt: day,
      endedAt: day.add(const Duration(minutes: 62)),
      exercises: <SessionExercise>[
        for (final (movement, sets) in work)
          SessionExercise(
            id: 'e${n++}',
            name: movement,
            orderIndex: n,
            sets: <SessionSet>[
              for (var i = 0; i < sets.length; i++)
                SessionSet(
                  id: 's${n}_$i',
                  setNumber: i + 1,
                  weightKg: sets[i].$1,
                  reps: sets[i].$2,
                  isCompleted: true,
                ),
            ],
          ),
      ],
    );
  }

  return <Session>[
    make(1, 'Push', <(String, List<(double, int)>)>[
      ('Barbell Bench Press', <(double, int)>[(80, 8), (85, 6), (90, 5)]),
      ('Dumbbell Shoulder Press', <(double, int)>[(26, 10), (26, 9)]),
      ('Cable Tricep Pushdown', <(double, int)>[(32, 12), (32, 11)]),
    ]),
    make(3, 'Pull', <(String, List<(double, int)>)>[
      ('Barbell Deadlift', <(double, int)>[(140, 5), (150, 3)]),
      ('Barbell Row', <(double, int)>[(70, 8), (70, 8)]),
    ]),
    make(5, 'Legs', <(String, List<(double, int)>)>[
      ('Barbell Back Squat', <(double, int)>[(110, 5), (115, 5), (120, 3)]),
      ('Romanian Deadlift', <(double, int)>[(90, 8)]),
    ]),
    make(8, 'Push', <(String, List<(double, int)>)>[
      ('Barbell Bench Press', <(double, int)>[(80, 8), (82.5, 7)]),
    ]),
    make(10, 'Pull', <(String, List<(double, int)>)>[
      ('Barbell Row', <(double, int)>[(67.5, 8), (67.5, 8)]),
    ]),
    // A fortnight's gap, because real logs have them and the streak copy has
    // to read correctly on both sides of one.
    make(31, 'Full Body', <(String, List<(double, int)>)>[
      ('Barbell Back Squat', <(double, int)>[(100, 5)]),
    ]),
  ];
}

class FakeHistory implements SessionHistory {
  const FakeHistory(this._log);

  final List<Session> _log;

  @override
  Future<List<Session>> all({int? limit}) async {
    final sorted = <Session>[..._log]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return limit == null ? sorted : sorted.take(limit).toList();
  }
}

/// A planner with canned answers, so the coach-backed sheets and the intake
/// conversation are reviewable without a network or an account.
///
/// The harness is the checklist the navigation audit works from, so a screen
/// missing from it is a screen nobody has looked at — which is exactly what
/// happened to these three.
class FakePlanner implements CoachPlanner {
  FakePlanner({this.failWith});

  final PlanFailure? failWith;

  void _maybeFail() {
    final f = failWith;
    if (f != null) throw PlanException(f);
  }

  @override
  Future<IntakeTurn> intake({
    required PlanIntake known,
    required List<PlannerTurn> history,
  }) async {
    _maybeFail();
    return IntakeTurn(
      reply:
          'Four days is plenty. Which days can you get there, and what have '
          'you got to train with?',
      extracted: const PlanIntake(
        goal: 'Get my bench past 100 by Christmas',
        daysPerWeek: 4,
        availableWeekdays: <int>[1, 2, 4, 5],
        equipment: 'Full gym',
      ),
    );
  }

  @override
  Future<List<PlanWeek>> skeleton({
    required PlanIntake intake,
    List<String> violations = const <String>[],
  }) async => const <PlanWeek>[];

  @override
  Future<WeekProposal> week({
    required PlanIntake intake,
    required PlanWeek slot,
    List<String> violations = const <String>[],
  }) async => const WeekProposal(sessions: <ProposedSession>[]);

  @override
  Future<SwapProposal> swap({
    required String message,
    required Session session,
  }) async {
    _maybeFail();
    return SwapProposal.fromJson(<String, Object?>{
      'reply':
          'Fair enough. Any of these train the same thing, and the first is '
          'kindest on the shoulder.',
      'swap': <String, Object?>{
        'replaces': 'Barbell Bench Press',
        'options': <Object?>[
          <String, Object?>{
            'name': 'Dumbbell Bench Press',
            'sets': 3,
            'reps': 8,
            'intensity_pct': null,
            'why': 'Same pattern, kinder on the shoulder',
          },
          <String, Object?>{
            'name': 'Machine Chest Press',
            'sets': 3,
            'reps': 10,
            'intensity_pct': null,
            'why': 'Fixed path, nothing to stabilise',
          },
        ],
      },
    });
  }

  @override
  Future<AdaptProposal> adapt({
    required String message,
    required Plan plan,
    required int weekNumber,
  }) async {
    _maybeFail();
    return AdaptProposal.fromJson(<String, Object?>{
      'reply':
          'I would move Thursday to Friday and go lighter on Monday. That '
          'gives the shoulder two more days before it takes any load.',
      'changes': <Object?>[
        <String, Object?>{
          'action': 'move',
          'weekday': 4,
          'to_weekday': 5,
          'movement': null,
          'to': null,
          'why': 'Two more days before it takes load',
        },
        <String, Object?>{
          'action': 'lighten',
          'weekday': 1,
          'to_weekday': null,
          'movement': null,
          'to': null,
          'why': 'A set off everything, ten per cent down',
        },
      ],
    });
  }
}
