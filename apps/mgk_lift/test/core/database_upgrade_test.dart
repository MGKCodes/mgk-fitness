import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';

/// Every TestFlight install holds a schema 7 database, and opens it with this
/// code on the first launch after the update. A migration that fails there
/// fails before the app draws anything.
void main() {
  /// The shape the current schema creates, less what schema 8 added — which is
  /// what a schema 7 install has on disk.
  Future<List<String>> schema7() async {
    final fresh = AppDatabase.memory();
    final rows = await fresh
        .customSelect(
          "select sql from sqlite_master where sql is not null "
          "and type in ('table', 'index') order by type desc",
        )
        .get();
    await fresh.close();
    return <String>[
      for (final r in rows)
        r
            .read<String>('sql')
            .replaceAll(RegExp(r',\s*"template_snapshot" TEXT( NULL)?'), ''),
    ];
  }

  test('a schema 7 database opens, upgrades, and keeps its sessions', () async {
    final statements = await schema7();
    expect(
      statements.firstWhere((s) => s.contains('"workouts"')),
      isNot(contains('template_snapshot')),
      reason: 'the fixture must really be the old shape',
    );

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
            ..execute('PRAGMA user_version = 7');
        },
      ),
    );
    addTearDown(db.close);

    final session = await db.select(db.workouts).getSingle();
    expect(session.name, 'Push');
    expect(session.templateSnapshot, isNull);
    expect(await db.select(db.exerciseSets).get(), hasLength(1));

    // The new column is there and takes a value.
    await (db.update(db.workouts)..where((w) => w.id.equals('w1'))).write(
      const WorkoutsCompanion(templateSnapshot: Value('[]')),
    );
    expect((await db.select(db.workouts).getSingle()).templateSnapshot, '[]');

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 8);
  });
}
