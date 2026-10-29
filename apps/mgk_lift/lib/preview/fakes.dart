import '../src/features/stats/domain/session_history.dart';
import '../src/features/sync/domain/sync_status.dart';
import '../src/features/planning/domain/plan_intake.dart';
import '../src/features/planning/domain/plan_builder.dart';
import '../src/features/planning/domain/plan_template.dart';
import '../src/features/planning/domain/standing_plan.dart';
import '../src/features/planning/domain/standing_plan_store.dart';
import '../src/features/planning/domain/training_split.dart';
import '../src/features/planning/domain/coach_planner.dart';
import '../src/features/planning/domain/intake_flow.dart';
import '../src/features/planning/domain/plan_proposal.dart';
import '../src/features/tracking/domain/session.dart';
import '../src/features/tracking/data/in_memory_session_recorder.dart';

/// The preview's name for [InMemorySessionRecorder], which moved into the
/// app when the walkthrough's practice set needed one. Kept so the harness's
/// many entries read as they did.
typedef FakeSessionRecorder = InMemorySessionRecorder;

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
  FakeHistory(Iterable<Session> log) : _log = <Session>[...log];

  final List<Session> _log;
  final Map<String, Session> _removed = <String, Session>{};

  @override
  Future<List<Session>> all({int? limit}) async {
    final sorted = <Session>[..._log]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return limit == null ? sorted : sorted.take(limit).toList();
  }

  @override
  Future<void> remove(String id) async {
    final at = _log.indexWhere((s) => s.id == id);
    if (at >= 0) _removed[id] = _log.removeAt(at);
  }

  @override
  Future<void> restore(String id) async {
    final back = _removed.remove(id);
    if (back != null) _log.add(back);
  }
}

/// A plan that says when the server last gave it, which the in-memory store
/// cannot: nothing in it was ever on a server (#2).
///
/// [offline] is the gym with no signal — the copy saved on the phone, said as
/// such. Without it, the plan has just been checked.
class FakePlanStore implements StandingPlanStore {
  FakePlanStore(this._plan, {required this.checkedAt, this.offline = false});

  StandingPlan _plan;
  final DateTime checkedAt;
  final bool offline;

  @override
  Future<StandingPlan?> active() async => _plan;

  @override
  Stream<PlanRead> watch() async* {
    yield PlanRead(
      _plan,
      freshness: offline ? PlanFreshness.unreachable : PlanFreshness.checked,
      checkedAt: checkedAt,
    );
  }

  @override
  Future<StandingPlan> replace(StandingPlan plan, {PlanIntake? intake}) async =>
      _plan = plan;
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
    required IntakeProgress progress,
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
  Future<PlanProposal> plan({
    required PlanIntake intake,
    required List<int> weekdays,
    required List<String> catalogue,
    List<String> violations = const <String>[],
  }) async {
    _maybeFail();
    // Built by the template rather than scripted, so the fake produces a plan
    // that clears PlanShape at any day count instead of one that happens to
    // pass at four.
    final split = TrainingSplit.forDays(weekdays.length);
    final slots = PlanTemplate.slotsFor(split: split, days: weekdays.length);
    final order = split.weekFor(weekdays.length);
    return PlanProposal(
      reply: split.why,
      name: split.name,
      days: <ProposedDay>[
        for (final day in order)
          ProposedDay(
            day: day,
            movements: <ProposedSlot>[
              for (final s in slots[day] ?? const <MovementSlot>[])
                ProposedSlot(
                  role: s.role,
                  movement: s.movement,
                  isMain: s.isMain,
                  sets: s.sets,
                  reps: s.reps,
                ),
            ],
          ),
      ],
    );
  }

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
}

/// Backup that answers the same way every time — for the plates that show
/// what a failure, a refusal or a quiet success looks like.
class FakeBackup implements BackupService {
  FakeBackup({
    this.report = const SyncReport(outcome: SyncOutcome.upToDate),
    this.waiting = const SyncPending(workouts: 0, lastSyncedAt: null),
  });

  final SyncReport report;
  final SyncPending waiting;

  @override
  Future<SyncPending> pending() async => waiting;

  @override
  Future<SyncReport> run() async => report;
}
