import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Schema 12 adds `plan_sessions.with_strength`, so a week keeps its strength
/// days on disk. A phone upgrading from schema 11 has weeks written before the
/// column existed, with their strength days already dropped: they must open,
/// and read back as the runs they stored, not as anything invented.
void main() {
  test('a schema 11 database upgrades, and its weeks read as they were', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = Directory.systemTemp.createTempSync('schema12');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/run.sqlite');

    // Today's schema minus what schema 12 added (and 13 after it), at version 11, with
    // a session row written the way schema 11 wrote them.
    var db = AppDatabase(NativeDatabase(file));
    await db.allRuns();
    await db.customStatement(
      'ALTER TABLE plan_sessions DROP COLUMN with_strength',
    );
    // And what schema 13 added since (ADR-0049), so the upgrade has it to add.
    for (final column in <String>[
      'race_distance_m',
      'race_time_s',
      'race_name',
    ]) {
      await db.customStatement('ALTER TABLE runs DROP COLUMN $column');
    }
    await db.customStatement('PRAGMA user_version = 11');
    await db.close();
    final raw = sqlite3.sqlite3.open(file.path);
    raw.execute(
      'INSERT INTO plan_sessions (plan_id, week_number, weekday, '
      'scheduled_date, kind, target_distance_m) '
      "VALUES ('plan-1', 1, 2, 1791244800, 'easy', 6000)",
    );
    raw.close();

    // The upgrade.
    db = AppDatabase(NativeDatabase(file));
    final rows = await db.sessionsForWeek('plan-1', 1);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    // The current version rather than 12: later schemas upgrade in the same
    // pass, and what this pins is that the schema 12 step ran within it.
    expect(version.data.values.first, db.schemaVersion);
    expect(rows, hasLength(1));
    expect(rows.single.kind, 'easy');
    expect(rows.single.targetDistanceM, 6000);
    expect(rows.single.withStrength, isFalse, reason: 'nothing to recover');
    await db.close();

    // And the column is there for the next week the builder writes.
    final check = sqlite3.sqlite3.open(file.path);
    final columns = check
        .select('PRAGMA table_info(plan_sessions)')
        .map((row) => row['name'] as String)
        .toSet();
    check.close();
    expect(columns, contains('with_strength'));
  });
}
