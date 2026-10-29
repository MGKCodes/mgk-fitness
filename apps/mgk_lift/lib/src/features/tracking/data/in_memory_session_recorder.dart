import '../domain/session.dart';
import '../domain/session_recorder.dart';

/// A [SessionRecorder] that keeps the session in memory and nowhere else.
///
/// **Two users, for one reason: neither may touch the database.**
///
/// - **The practice set** in the walkthrough (ADR-0006). A lifter's first set
///   is logged for real, in the real session screen, and is kept nowhere: not
///   on the phone, not in a backup, not in history, bests, the log or the
///   weights a plan works out from it, and never offered back as a session to
///   resume. A recorder with no storage under it is the only way all of that
///   is true by construction rather than by every reader remembering to
///   leave one session out.
/// - **The preview harness.** The real recorder writes to SQLite through
///   `sqlite3_flutter_libs`, which does not exist on web without a WASM
///   build, and the harness is there to review screens, not to stand up a
///   database to look at them.
///
/// Lived in `lib/preview/fakes.dart` as `FakeSessionRecorder` until the
/// practice set needed it in the app. It keeps the real recorder's rules
/// where a screen can see them: a swap keeps logged work and puts the
/// replacement beneath it, Finish drops unticked sets and empty movements,
/// and positions stay contiguous.
class InMemorySessionRecorder implements SessionRecorder {
  InMemorySessionRecorder([Session? session]) : _current = session;

  Session? _current;
  int _ids = 0;

  /// Told the session after every change, as it now stands (null once it is
  /// finished or discarded). What lets the walkthrough see the practice set
  /// ticked without reaching into the screen that ticked it.
  void Function(Session? session)? onChanged;

  Session? get _session => _current;
  set _session(Session? session) {
    _current = session;
    onChanged?.call(session);
  }

  String get _nextId => 'p${++_ids}';

  @override
  Future<Session?> current() async => _session;

  @override
  Future<Session> start({String? name, DateTime? at}) async {
    if (_session != null) throw const SessionInProgress();
    return _session = Session(
      id: 'in-memory',
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
  Future<Session> fillFromLibrary({
    required String workoutId,
    required String name,
    required List<SeededMovement> movements,
    String? snapshot,
  }) async {
    final s = _require();
    return _session = Session(
      id: s.id,
      name: name,
      startedAt: s.startedAt,
      endedAt: s.endedAt,
      notes: s.notes,
      templateId: workoutId,
      templateSnapshot: snapshot,
      exercises: <SessionExercise>[
        ...s.exercises,
        for (var i = 0; i < movements.length; i++)
          SessionExercise(
            id: _nextId,
            name: movements[i].name,
            orderIndex: s.exercises.length + i,
            sets: <SessionSet>[
              for (var n = 0; n < movements[i].sets.length; n++)
                SessionSet(
                  id: _nextId,
                  setNumber: n + 1,
                  reps: movements[i].sets[n].reps,
                  weightKg: movements[i].sets[n].weightKg,
                ),
            ],
          ),
      ],
    );
  }

  @override
  Future<Session> addExercises(List<String> names) async {
    var s = _require();
    for (final name in names) {
      s = await addExercise(name);
    }
    return s;
  }

  @override
  Future<Session> addSet(
    String exerciseId, {
    int? reps,
    double? weightKg,
  }) async {
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
                reps: e.sets.isEmpty ? (reps ?? 0) : e.sets.last.reps,
                weightKg: e.sets.isEmpty
                    ? (weightKg ?? 0)
                    : e.sets.last.weightKg,
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
        _withSets(e, e.sets.where((x) => x.id != setId).toList()),
    ]);
  }

  @override
  Future<Session> restoreSet(String exerciseId, SessionSet set) async {
    final s = _require();
    return _session = _copy(s, <SessionExercise>[
      for (final e in s.exercises)
        if (e.id != exerciseId)
          e
        else
          _withSets(
            e,
            <SessionSet>[...e.sets]
              ..insert((set.setNumber - 1).clamp(0, e.sets.length), set),
          ),
    ]);
  }

  @override
  Future<Session> removeExercise(String exerciseId) async {
    final s = _require();
    return _session = _copy(
      s,
      _positioned(s.exercises.where((e) => e.id != exerciseId).toList()),
    );
  }

  @override
  Future<Session> restoreExercise(SessionExercise exercise) async {
    final s = _require();
    final list = <SessionExercise>[...s.exercises]
      ..insert(exercise.orderIndex.clamp(0, s.exercises.length), exercise);
    return _session = _copy(s, _positioned(list));
  }

  @override
  Future<Session> replaceExercise(
    String exerciseId,
    String name, {
    int sets = 0,
    int? reps,
    double? weightKg,
  }) async {
    final s = _require();
    final list = <SessionExercise>[...s.exercises];
    final at = list.indexWhere((e) => e.id == exerciseId);
    if (at < 0) return s;
    final replacement = SessionExercise(
      id: _nextId,
      name: name,
      orderIndex: 0,
      sets: <SessionSet>[
        for (var i = 0; i < sets; i++)
          SessionSet(
            id: _nextId,
            setNumber: i + 1,
            reps: reps ?? 0,
            weightKg: weightKg ?? 0,
          ),
      ],
    );
    // Same rule as the real recorder: logged work stays and the replacement
    // goes beneath it; with nothing logged it is replaced where it stands.
    if (list[at].sets.any((x) => x.isCompleted)) {
      list.insert(at + 1, replacement);
    } else {
      list[at] = replacement;
    }
    return _session = _copy(s, _positioned(list));
  }

  @override
  Future<Session> moveExercise(String exerciseId, int toIndex) async {
    final s = _require();
    final list = <SessionExercise>[...s.exercises];
    final from = list.indexWhere((e) => e.id == exerciseId);
    if (from < 0) return s;
    final moved = list.removeAt(from);
    list.insert(toIndex.clamp(0, list.length), moved);
    return _session = _copy(s, _positioned(list));
  }

  @override
  Future<Session> finish({DateTime? at}) async {
    final s = _require();
    // Unticked sets did not happen, and neither did a movement left empty —
    // the real recorder's rule, so a summary here reads as the app's does.
    final kept = <SessionExercise>[
      for (final e in s.exercises)
        if (e.sets.any((x) => x.isCompleted))
          _withSets(e, e.sets.where((x) => x.isCompleted).toList()),
    ];
    final done = Session(
      id: s.id,
      name: s.name,
      startedAt: s.startedAt,
      endedAt: at ?? DateTime.now(),
      exercises: _positioned(kept),
      templateId: s.templateId,
      templateSnapshot: s.templateSnapshot,
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

  // Through `withExercises`, which carries the saved workout the session came
  // from. Built by hand, this dropped it on the first tick — and the harness
  // then showed a summary that never learned, and offered a copy instead.
  Session _copy(Session s, List<SessionExercise> exercises) =>
      s.withExercises(exercises);

  /// The movement with [sets], renumbered from one.
  static SessionExercise _withSets(SessionExercise e, List<SessionSet> sets) =>
      SessionExercise(
        id: e.id,
        name: e.name,
        orderIndex: e.orderIndex,
        notes: e.notes,
        cardioMode: e.cardioMode,
        sets: <SessionSet>[
          for (var i = 0; i < sets.length; i++)
            SessionSet(
              id: sets[i].id,
              setNumber: i + 1,
              reps: sets[i].reps,
              weightKg: sets[i].weightKg,
              isCompleted: sets[i].isCompleted,
              setType: sets[i].setType,
              durationS: sets[i].durationS,
              distanceM: sets[i].distanceM,
            ),
        ],
      );

  /// The movements, with positions made contiguous again.
  static List<SessionExercise> _positioned(List<SessionExercise> list) =>
      <SessionExercise>[
        for (var i = 0; i < list.length; i++)
          SessionExercise(
            id: list[i].id,
            name: list[i].name,
            orderIndex: i,
            notes: list[i].notes,
            cardioMode: list[i].cardioMode,
            sets: list[i].sets,
          ),
      ];
}
