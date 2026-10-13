import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/history/data/drift_run_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Schema 13 adds the race to the run (ADR-0049). A phone upgrading from 12
/// has runs written before the columns existed: they must open, read back as
/// the training runs they were recorded as, and nothing may be filed as a race
/// on the runner's behalf.
void main() {
  test('a schema 12 database upgrades, and its runs are not races', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = Directory.systemTemp.createTempSync('schema13');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/run.sqlite');

    // Today's schema minus what schema 13 added, at version 12, with a run
    // written the way schema 12 wrote them.
    var db = AppDatabase(NativeDatabase(file));
    await db.allRuns();
    for (final column in <String>[
      'race_distance_m',
      'race_time_s',
      'race_name',
    ]) {
      await db.customStatement('ALTER TABLE runs DROP COLUMN $column');
    }
    await db.customStatement('PRAGMA user_version = 12');
    await db.close();
    final raw = sqlite3.sqlite3.open(file.path);
    raw.execute(
      'INSERT INTO runs (id, started_at, ended_at, duration_s, distance_m, '
      "source, type) VALUES ('sunday', 1791700000, 1791707247, 7247, "
      "21685.8, 'gps', 'outdoor')",
    );
    raw.close();

    // The upgrade.
    db = AppDatabase(NativeDatabase(file));
    final run = await DriftRunRepository(db).runDetail('sunday');
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, db.schemaVersion);
    expect(run, isNotNull);
    expect(run!.distanceMeters, 21685.8);
    expect(run.race, isNull, reason: 'not a race until the runner says so');
    await db.close();

    final check = sqlite3.sqlite3.open(file.path);
    final columns = check
        .select('PRAGMA table_info(runs)')
        .map((row) => row['name'] as String)
        .toSet();
    check.close();
    expect(
      columns,
      containsAll(<String>['race_distance_m', 'race_time_s', 'race_name']),
    );
  });
}
