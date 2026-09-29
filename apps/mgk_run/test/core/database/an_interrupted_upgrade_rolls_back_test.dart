// Regression for EDGE-9: `onUpgrade` used to run its steps one at a time with
// no transaction, and drift only bumps `PRAGMA user_version` once the whole
// callback returns. A process killed between two steps left whichever
// statements *had* run in place, the version still at the old number, and
// every later launch re-running the same steps and hitting "duplicate column
// name" / "table already exists" forever, from a database no launch could
// open again (see the throwaway reproduction under
// .claude/worktrees/review-edge/apps/mgk_run/test/zz_edge_review/half_migrated_db_test.dart,
// whose technique for building a genuine old-schema database this borrows).
//
// `AppDatabase.migration.onUpgrade` now wraps every step in `transaction()`.
// This proves the consequence for a *multi-step* interruption specifically:
// forces the conflict at schema 10, after schema 8 (two column adds) and
// schema 9 (a table create *and* a real backfill) have genuinely run earlier
// in the same attempt, and checks that every one of those earlier steps was
// undone along with the one that failed — not just the statement that threw.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('an upgrade interrupted partway rolls back every earlier step too, so '
      'the next launch succeeds', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = Directory.systemTemp.createTempSync('edge9_rollback');
    final file = File('${dir.path}/runio.sqlite');

    // A genuine schema-7 shape: today's schema minus everything schema 8,
    // 9, 10 and 11 added.
    var db = AppDatabase(NativeDatabase(file));
    await db.allRuns(); // creates fresh, at the current schemaVersion
    await db.customStatement('DROP TABLE run_best_efforts');
    await db.customStatement('ALTER TABLE runs DROP COLUMN elevation_max_m');
    await db.customStatement('ALTER TABLE runs DROP COLUMN steps');
    await db.customStatement('ALTER TABLE runs DROP COLUMN paused_total_s');
    await db.customStatement('ALTER TABLE runs DROP COLUMN not_counting_since');
    await db.customStatement('ALTER TABLE plans DROP COLUMN race_time_s');
    // `plans.finished_at` is deliberately left in place — standing in for
    // "schema 10's first statement already landed from an earlier
    // interrupted attempt" — so schema 8 (two plain column adds) and
    // schema 9 (a table create *and* a real backfill over it) both run to
    // completion this attempt before the real, unmodified onUpgrade hits a
    // genuine conflict at schema 10's own `addColumn`.
    await db.customStatement('PRAGMA user_version = 7');
    await db.close();

    // Launch 1: onUpgrade runs 7 -> current, completes schema 8 and 9 for
    // real, and throws at schema 10's conflict.
    db = AppDatabase(NativeDatabase(file));
    Object? firstError;
    try {
      await db.allRuns();
    } catch (e) {
      firstError = e;
    }
    expect(firstError, isNotNull);
    await db.close();

    // Inspect the file directly, bypassing AppDatabase entirely — opening
    // it through drift again would immediately retry (and re-fail) the
    // same migration before any query of ours ran. This is the actual
    // proof: schema 8 and 9 both ran without error in this attempt, so a
    // migration that committed as it went (the pre-fix behaviour) would
    // leave both in place despite the attempt failing at schema 10.
    final raw = sqlite3.sqlite3.open(file.path);
    final version = raw.select('PRAGMA user_version').first.values.first;
    expect(
      version,
      7,
      reason: 'the failed attempt must not have bumped the version',
    );
    final runsColumns = raw
        .select('PRAGMA table_info(runs)')
        .map((row) => row['name'] as String)
        .toSet();
    expect(
      runsColumns.contains('elevation_max_m'),
      isFalse,
      reason:
          "schema 8's own addColumn ran cleanly this attempt, but "
          'must still have been rolled back with everything after it',
    );
    expect(runsColumns.contains('steps'), isFalse);
    final tables = raw
        .select("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row['name'] as String)
        .toSet();
    expect(
      tables.contains('run_best_efforts'),
      isFalse,
      reason:
          'schema 9 created this table and backfilled it for real '
          'this attempt, and must still have been rolled back',
    );
    raw.close();

    // Remove the one thing standing in for "the interruption" — again
    // bypassing AppDatabase, so the repair itself does not trip the same
    // migration attempt.
    final repair = sqlite3.sqlite3.open(file.path);
    repair.execute('ALTER TABLE plans DROP COLUMN finished_at');
    repair.close();

    // Launch 2: nothing stands in the way any more, so the retry succeeds
    // cleanly and reaches the current schema — which it could not do if
    // schema 8 or 9 had actually been left applied by the failed attempt
    // above (their own steps would then conflict, just as schema 10's did).
    db = AppDatabase(NativeDatabase(file));
    await db.allRuns();
    final reached = await db.customSelect('PRAGMA user_version').getSingle();
    expect(reached.data.values.first, db.schemaVersion);
    await db.close();

    dir.deleteSync(recursive: true);
  });
}
