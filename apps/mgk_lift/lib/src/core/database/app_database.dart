import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// The on-device database — the offline-first source of truth for a session in
/// progress.
///
/// Supabase is a backup and cross-device store, never the authority for a set
/// being logged right now. A lifter is standing at a rack in a basement; the
/// network is optional and the database is not.
///
/// The coach is the other half of the app and takes the opposite posture: it
/// needs a connection and says so. Nothing here depends on it.
@DriftDatabase(
  tables: [Workouts, Exercises, ExerciseSets, ProgressPhotos, SyncMeta],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the real on-device database file.
  AppDatabase.open() : this(_openConnection());

  /// In-memory, for tests. Every test gets its own database and none of them
  /// touch the disk.
  AppDatabase.memory() : this(NativeDatabase.memory());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Warm-up sets, so they can be kept out of volume and personal bests.
        // Defaulted to 'working', which is what every existing row was — the
        // concept did not exist, so nothing was a warm-up.
        await m.addColumn(exerciseSets, exerciseSets.setType);
      }
      if (from < 3) {
        // Progress photos. A new table rather than a column, so nothing
        // existing is touched.
        await m.createTable(progressPhotos);
      }
      if (from < 4) {
        // Sync. `syncedAt` stays null on every existing row, which is exactly
        // right: nothing has ever been uploaded, so everything is pending.
        await m.addColumn(workouts, workouts.syncedAt);
        await m.createTable(syncMeta);
      }
      if (from < 5) {
        // Where a saved workout came from, when it came from one of the
        // fifteen. Null on every existing row and that is correct — nothing in
        // the app has ever written a template, so no row can have an origin.
        //
        // Deliberately landed *before* the write path rather than after it. A
        // column added later would need a backfill guessing which meaning each
        // existing `templateId` carried; added now there is nothing to guess.
        await m.addColumn(workouts, workouts.premadeId);
      }
      if (from < 6) {
        // Photos go to the bucket now. Null on every existing row, which is
        // exactly right: nothing has ever been uploaded, so every photo a
        // lifter already has counts as pending and goes up on the first run.
        await m.addColumn(progressPhotos, progressPhotos.syncedAt);
      }
      // The slot rule, as an index rather than a table constraint: drift's
      // `customConstraints` replaces the generated ones wholesale, and a
      // partial unique index is the only way to say "one live photo per week
      // per pose" while still keeping soft-deleted rows around.
      await customStatement(
        'create unique index if not exists progress_photos_slot '
        'on progress_photos (week_start, pose_type) where deleted_at is null',
      );
    },
    beforeOpen: (details) async {
      // Off by default in SQLite, and the cascade from Workouts through
      // Exercises to ExerciseSets is the thing that stops a deleted session
      // leaving orphaned sets behind.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    return NativeDatabase.createInBackground(
      File(p.join(dir.path, 'mgk_lift.sqlite')),
    );
  });
}
