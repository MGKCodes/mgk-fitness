import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';

/// Every TestFlight install holds an older database, and opens it with this
/// code on the first launch after the update. A migration that fails there
/// fails before the app draws anything.
void main() {
  /// What each version added to the shape, so an older one can be rebuilt by
  /// taking it away from the current one.
  const addedAfter = <int, List<String>>{
    // 7 added indexes only.
    7: <String>[],
    8: <String>['template_snapshot'],
    9: <String>['sync_error', 'sync_attempts', 'last_sync_attempt_at'],
  };
  const indexesFrom7 = <String>[
    'exercises_workout_order',
    'exercise_sets_exercise_number',
    'progress_photos_slot',
  ];

  /// The current shape less everything added after [version].
  Future<List<String>> shapeAt(int version) async {
    final fresh = AppDatabase.memory();
    final rows = await fresh
        .customSelect(
          "select name, sql from sqlite_master where sql is not null "
          "and type in ('table', 'index') order by type desc",
        )
        .get();
    await fresh.close();

    final dropColumns = <String>[
      for (final e in addedAfter.entries)
        if (e.key > version) ...e.value,
    ];
    return <String>[
      for (final r in rows)
        if (version >= 7 || !indexesFrom7.contains(r.read<String>('name')))
          dropColumns.fold(
            r.read<String>('sql'),
            (sql, column) =>
                sql.replaceAll(RegExp(',\\s*"$column" [^,)]*'), ''),
          ),
    ];
  }

  for (final version in <int>[6, 8]) {
    test('a schema $version database opens, upgrades, and keeps its '
        'sessions', () async {
      final statements = await shapeAt(version);
      final workouts = statements.firstWhere((s) => s.contains('"workouts"'));
      expect(
        workouts,
        isNot(contains('sync_error')),
        reason: 'the fixture must really be the old shape',
      );
      expect(workouts.contains('template_snapshot'), version >= 8);

      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            for (final s in statements) {
              raw.execute(s);
            }
            raw
              ..execute(
                'insert into workouts (id, name, started_at, ended_at) '
                "values ('w1', 'Push', 1790000000, 1790003600)",
              )
              ..execute(
                "insert into exercises (id, workout_id, name) "
                "values ('e1', 'w1', 'Barbell Bench Press')",
              )
              ..execute(
                'insert into exercise_sets (id, exercise_id, reps, weight_kg, '
                "is_completed) values ('s1', 'e1', 5, 100, 1)",
              )
              ..execute('PRAGMA user_version = $version');
          },
        ),
      );
      addTearDown(db.close);

      final session = await db.select(db.workouts).getSingle();
      expect(session.name, 'Push');
      expect(session.templateSnapshot, isNull);
      expect(session.syncError, isNull);
      expect(session.syncAttempts, 0);
      expect(await db.select(db.exerciseSets).get(), hasLength(1));

      // The new columns are there and take values.
      await (db.update(db.workouts)..where((w) => w.id.equals('w1'))).write(
        const WorkoutsCompanion(
          templateSnapshot: Value('[]'),
          syncError: Value('23514: check'),
          syncAttempts: Value(2),
        ),
      );
      final after = await db.select(db.workouts).getSingle();
      expect(after.templateSnapshot, '[]');
      expect(after.syncError, '23514: check');

      final indexes = await db
          .customSelect("select name from sqlite_master where type = 'index'")
          .get();
      expect(
        indexes.map((r) => r.read<String>('name')),
        containsAll(indexesFrom7),
      );

      final current = await db.customSelect('PRAGMA user_version').getSingle();
      expect(current.data.values.single, 9);
    });
  }
}
