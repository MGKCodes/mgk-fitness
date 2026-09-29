import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/sync/data/workout_backup.dart';
import 'package:mgk_lift/src/features/sync/domain/backup_remote.dart';
import 'package:mgk_lift/src/features/sync/domain/sync_status.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_workout_library.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';

/// A server in memory: what was saved, what to refuse, and what to hand back.
class FakeRemote implements BackupRemote {
  @override
  String? userId = 'user-1';

  final List<Map<String, Object?>> saved = <Map<String, Object?>>[];

  /// Ids the server refuses, with the refusal.
  final Map<String, BackupFailure> refuse = <String, BackupFailure>{};

  /// A failure that is not about any row — thrown on the next save.
  BackupFailure? down;

  /// Rows the pull hands back.
  List<Map<String, dynamic>> changes = <Map<String, dynamic>>[];

  /// Called during a save, before it lands — for edits made mid-upload.
  Future<void> Function(Map<String, Object?> workout)? whileSaving;

  /// The server's own clock, which stamps every write — and which need not
  /// agree with the phone's.
  DateTime serverClock = DateTime.utc(2026, 9, 29, 10);

  /// What the pull was last asked for.
  DateTime? askedSince;

  String _stamp() {
    serverClock = serverClock.add(const Duration(minutes: 1));
    return serverClock.toIso8601String();
  }

  @override
  Future<void> save(Map<String, Object?> workout) async {
    await whileSaving?.call(workout);
    final failure = down ?? refuse[workout['id']];
    if (failure != null) throw failure;
    saved.add(workout);
    // What a server does: stamps the write with its own clock, and the next
    // read returns it.
    changes = <Map<String, dynamic>>[
      for (final c in changes)
        if (c['id'] != workout['id']) c,
      <String, dynamic>{...workout, 'updated_at': _stamp()},
    ];
  }

  /// Puts a row on the server as another phone would.
  void written(Map<String, dynamic> row) => changes = <Map<String, dynamic>>[
    for (final c in changes)
      if (c['id'] != row['id']) c,
    <String, dynamic>{...row, 'updated_at': _stamp()},
  ];

  @override
  Future<List<Map<String, dynamic>>> changedSince(DateTime? since) async {
    if (down != null) throw down!;
    askedSince = since;
    return <Map<String, dynamic>>[
      for (final c in changes)
        if (since == null ||
            DateTime.parse(c['updated_at'] as String).isAfter(since))
          c,
    ]..sort(
      (a, b) =>
          (a['updated_at'] as String).compareTo(b['updated_at'] as String),
    );
  }
}

void main() {
  late AppDatabase db;
  late FakeRemote remote;
  late WorkoutBackup backup;
  var ids = 0;

  setUp(() {
    ids = 0;
    db = AppDatabase.memory();
    remote = FakeRemote();
    backup = WorkoutBackup(db, remote);
  });

  tearDown(() async => db.close());

  /// A finished session with one movement and [sets] sets.
  Future<String> session(
    String id, {
    int sets = 2,
    String name = 'Push',
  }) async {
    await db
        .into(db.workouts)
        .insert(
          WorkoutsCompanion.insert(
            id: id,
            name: name,
            startedAt: DateTime(2026, 9, 28, 18),
            endedAt: Value(DateTime(2026, 9, 28, 19)),
            durationS: const Value(3600),
          ),
        );
    await db
        .into(db.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: '$id-e',
            workoutId: id,
            name: 'Barbell Bench Press',
          ),
        );
    for (var n = 1; n <= sets; n++) {
      await db
          .into(db.exerciseSets)
          .insert(
            ExerciseSetsCompanion.insert(
              id: '$id-s$n',
              exerciseId: '$id-e',
              setNumber: Value(n),
              reps: const Value(5),
              weightKg: const Value(100),
              isCompleted: const Value(true),
            ),
          );
    }
    return id;
  }

  group('what goes up', () {
    test('a finished session, whole, in one request', () async {
      await session('s1');
      final report = await backup.run();

      expect(report.pushed, 1);
      final sent = remote.saved.single;
      expect(sent['id'], 's1');
      expect(sent['is_template'], isFalse);
      expect(sent['started_at'], isNotNull);
      final exercises = sent['exercises']! as List<Object?>;
      final sets =
          (exercises.single! as Map<String, Object?>)['sets']! as List<Object?>;
      expect(sets, hasLength(2));
      expect(await backup.pending().then((p) => p.workouts), 0);
    });

    test('a saved workout, as a template with no date', () async {
      final library = DriftWorkoutLibrary(db, idFactory: () => 'id-${++ids}');
      await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[
          TemplateMovement('Bench', sets: 4, repTarget: 5),
        ],
        fromPremade: 'push',
      );

      await backup.run();

      final sent = remote.saved.single;
      expect(sent['is_template'], isTrue);
      // What `workouts_template_has_no_date` requires.
      expect(sent['started_at'], isNull);
      expect(sent['premade_id'], 'push');
      final movement =
          (sent['exercises']! as List<Object?>).single! as Map<String, Object?>;
      expect(movement['sets'], hasLength(4));
    });

    test('a deleted workout goes up as a tombstone', () async {
      final library = DriftWorkoutLibrary(db, idFactory: () => 'id-${++ids}');
      final saved = await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[TemplateMovement('Bench')],
      );
      await backup.run();
      remote.saved.clear();

      // A second later, so the delete is newer than the upload.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await library.remove(saved.id);
      await backup.run();

      expect(remote.saved.single['deleted_at'], isNotNull);
    });

    test('never a session in progress', () async {
      await db
          .into(db.workouts)
          .insert(
            WorkoutsCompanion.insert(
              id: 'open',
              name: 'Push',
              startedAt: DateTime(2026, 9, 29),
            ),
          );
      await backup.run();
      expect(remote.saved, isEmpty);
    });

    test('signed out, nothing is sent and nothing is lost', () async {
      await session('s1');
      remote.userId = null;

      final report = await backup.run();

      expect(report.outcome, SyncOutcome.signedOut);
      expect(remote.saved, isEmpty);
      expect((await backup.pending()).workouts, 1);
    });
  });

  group('one bad row cannot block the rest', () {
    test('a refused workout is set aside; the others go', () async {
      await session('bad', name: 'Legs');
      await session('good');
      remote.refuse['bad'] = const BackupFailure(
        BackupProblem.rejected,
        '22003: value out of range',
      );

      final report = await backup.run();

      expect(report.isFailure, isFalse);
      expect(report.pushed, 1);
      expect(report.rejected, 1);
      expect(remote.saved.single['id'], 'good');

      final pending = await backup.pending();
      expect(pending.workouts, 0);
      expect(pending.rejected.single.name, 'Legs');
      expect(
        rejectionReason(pending.rejected.single.detail),
        'a value is out of range',
      );
    });

    test('and is not sent again until it is edited', () async {
      await session('bad');
      remote.refuse['bad'] = const BackupFailure(
        BackupProblem.rejected,
        '23514: check',
      );
      await backup.run();
      await backup.run();
      expect(remote.saved, isEmpty);
      final row = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals('bad'))).getSingle();
      expect(row.syncAttempts, 1, reason: 'tried once, not every run');
    });

    test('no connection stops the run, and every row stays waiting', () async {
      await session('a');
      await session('b');
      remote.down = const BackupFailure(BackupProblem.offline, 'socket');

      final report = await backup.run();

      expect(report.isFailure, isTrue);
      expect(report.problem, BackupProblem.offline);
      final pending = await backup.pending();
      expect(pending.workouts, 2);
      expect(pending.rejected, isEmpty);
    });

    test('and when it comes back, they go', () async {
      await session('a');
      remote.down = const BackupFailure(BackupProblem.server, '503');
      await backup.run();

      remote.down = null;
      final report = await backup.run();

      expect(report.pushed, 1);
      expect((await backup.pending()).workouts, 0);
    });

    test(
      'an edit made while the upload was in flight goes next time',
      () async {
        await session('a');
        remote.whileSaving = (_) async {
          remote.whileSaving = null;
          // A second on, so the edit is newer even to the second.
          await Future<void>.delayed(const Duration(milliseconds: 1100));
          await (db.update(db.workouts)..where((w) => w.id.equals('a'))).write(
            WorkoutsCompanion(
              name: const Value('Push, renamed'),
              updatedAt: Value(DateTime.now()),
            ),
          );
        };

        await backup.run();
        expect((await backup.pending()).waitingIds, contains('a'));

        await backup.run();
        expect(remote.saved.last['name'], 'Push, renamed');
      },
    );
  });

  group('what comes down', () {
    Map<String, dynamic> template({String? deletedAt, String? notes}) =>
        <String, dynamic>{
          'id': 't1',
          'name': 'Push',
          'started_at': null,
          'is_template': true,
          'premade_id': 'push',
          'deleted_at': deletedAt,
          'notes': notes,
          'created_at': '2026-09-01T10:00:00Z',
          'exercises': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 't1-e',
              'name': 'Bench',
              'order_index': 0,
              'sets': <Map<String, dynamic>>[
                <String, dynamic>{'id': 't1-s1', 'set_number': 1, 'reps': 5},
              ],
            },
          ],
        };

    test('a saved workout from another phone joins the library', () async {
      remote.written(template());
      await backup.run();

      final library = DriftWorkoutLibrary(db);
      final all = await library.all();
      expect(all.single.name, 'Push');
      expect(all.single.movements.single.repTarget, 5);
      expect((await backup.pending()).workouts, 0, reason: 'not sent back up');
    });

    test('a restore on another phone comes down', () async {
      // Deleted there, pulled here, restored there. A row object left the
      // null out, and the workout stayed deleted on this phone.
      remote.written(template(deletedAt: '2026-09-02T11:00:00Z'));
      await backup.run();
      expect(await DriftWorkoutLibrary(db).all(), isEmpty);

      remote.written(template());
      await backup.run();
      expect(await DriftWorkoutLibrary(db).all(), hasLength(1));
    });

    test('a note cleared on another phone clears here', () async {
      remote.written(template(notes: 'heavy'));
      await backup.run();
      remote.written(template());
      await backup.run();
      final row = await db.select(db.workouts).getSingle();
      expect(row.notes, isNull);
    });

    test('an edit that went up comes back as itself', () async {
      remote.written(template());
      await backup.run();
      await (db.update(db.workouts)..where((w) => w.id.equals('t1'))).write(
        WorkoutsCompanion(
          name: const Value('Push, mine'),
          updatedAt: Value(DateTime.now().add(const Duration(days: 1))),
        ),
      );
      // Pushed first, so the server has the edit before the pull runs.
      await backup.run();
      expect(remote.saved.single['name'], 'Push, mine');
      expect((await db.select(db.workouts).getSingle()).name, 'Push, mine');
    });

    test('a local edit not yet sent is not overwritten', () async {
      remote.written(template());
      await backup.run();
      await (db.update(db.workouts)..where((w) => w.id.equals('t1'))).write(
        WorkoutsCompanion(
          name: const Value('Push, mine'),
          updatedAt: Value(DateTime.now().add(const Duration(days: 1))),
        ),
      );
      // Refused, so it stays unsent — and another phone's older copy comes
      // down in the same run. The edit must win on this phone.
      remote.refuse['t1'] = const BackupFailure(
        BackupProblem.rejected,
        '23514: check',
      );
      remote.written(template());
      await backup.run();
      expect((await db.select(db.workouts).getSingle()).name, 'Push, mine');
    });

    test("a session's snapshot of its workout survives a pull", () async {
      await session('s1');
      await (db.update(db.workouts)..where((w) => w.id.equals('s1'))).write(
        const WorkoutsCompanion(templateSnapshot: Value('[{"name":"Bench"}]')),
      );
      await backup.run();
      remote.written(<String, dynamic>{
        'id': 's1',
        'name': 'Push',
        'started_at': '2026-09-28T17:00:00Z',
        'duration_s': 3600,
        'is_template': false,
        'exercises': <Map<String, dynamic>>[],
      });
      await backup.run();
      final row = await db.select(db.workouts).getSingle();
      expect(row.templateSnapshot, '[{"name":"Bench"}]');
    });
  });

  group('two clocks', () {
    test('the pull asks from the newest server time it has seen', () async {
      // The phone's own time was the watermark. On a phone running ahead of
      // the server, anything written in the gap was never pulled.
      remote.written(<String, dynamic>{
        'id': 'x',
        'name': 'Pull',
        'started_at': '2026-09-28T17:00:00Z',
        'duration_s': 60,
        'is_template': false,
        'exercises': <Map<String, dynamic>>[],
      });
      final stamped = DateTime.parse(
        remote.changes.single['updated_at'] as String,
      );

      await backup.run();
      await backup.run();

      expect(remote.askedSince!.isAtSameMomentAs(stamped), isTrue);
    });

    test(
      'a phone behind the server does not send the same row forever',
      () async {
        // The server's clock a day ahead of this phone's. Its stamp used to be
        // written into the local row, which then looked edited on every run.
        remote.serverClock = DateTime.now().toUtc().add(
          const Duration(days: 1),
        );
        await session('s1');

        await backup.run();
        expect(remote.saved, hasLength(1));
        await backup.run();
        await backup.run();

        expect(remote.saved, hasLength(1));
        expect((await backup.pending()).workouts, 0);
      },
    );

    test('"last backed up" is when the run finished, on this phone', () async {
      await session('s1');
      await backup.run();
      final last = (await backup.pending()).lastSyncedAt!;
      expect(DateTime.now().difference(last).inMinutes, lessThan(1));
    });
  });

  group('rejectionReason', () {
    test('says what was wrong, never the code', () {
      expect(
        rejectionReason('22003: numeric overflow'),
        'a value is out of range',
      );
      expect(rejectionReason('23514: violates check'), "a value isn't allowed");
      expect(
        rejectionReason('23502: null value'),
        'something it needs is missing',
      );
      expect(
        rejectionReason('XX000: who knows'),
        "the server wouldn't take it",
      );
    });
  });
}
