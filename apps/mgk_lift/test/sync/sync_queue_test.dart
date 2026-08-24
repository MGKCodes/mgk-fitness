import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/sync/data/sync_queue.dart';

void main() {
  late AppDatabase db;
  late SyncQueue queue;

  setUp(() {
    db = AppDatabase.memory();
    queue = SyncQueue(db);
  });

  tearDown(() async => db.close());

  Future<void> insert({
    required String id,
    DateTime? endedAt,
    DateTime? syncedAt,
    DateTime? updatedAt,
  }) => db
      .into(db.workouts)
      .insert(
        WorkoutsCompanion.insert(
          id: id,
          name: 'Session',
          startedAt: DateTime(2026, 8, 3),
          endedAt: Value(endedAt),
          syncedAt: Value(syncedAt),
          updatedAt: Value(updatedAt ?? DateTime(2026, 8, 3, 12)),
        ),
      );

  group('what needs uploading', () {
    test('a finished session that has never been uploaded', () async {
      await insert(id: 'a', endedAt: DateTime(2026, 8, 3, 11));
      expect(await queue.dirtyWorkouts(), hasLength(1));
    });

    test('a session in progress is never uploaded', () async {
      // The remote schema cannot express one: the template CHECK demands a
      // started_at on any non-template, and the activity trigger would file a
      // half-logged session into the cross-app feed the moment it landed.
      await insert(id: 'open');
      expect(await queue.dirtyWorkouts(), isEmpty);
    });

    test('an uploaded session with no edits since is left alone', () async {
      await insert(
        id: 'a',
        endedAt: DateTime(2026, 8, 3, 11),
        updatedAt: DateTime(2026, 8, 3, 12),
        syncedAt: DateTime(2026, 8, 3, 13),
      );
      expect(await queue.dirtyWorkouts(), isEmpty);
    });

    test('editing an uploaded session makes it dirty again', () async {
      await insert(
        id: 'a',
        endedAt: DateTime(2026, 8, 3, 11),
        updatedAt: DateTime(2026, 8, 4, 9),
        syncedAt: DateTime(2026, 8, 3, 13),
      );
      expect(await queue.dirtyWorkouts(), hasLength(1));
    });
  });

  group('marking as synced', () {
    test('does not touch updatedAt, or the sync never converges', () async {
      // Writing updatedAt here would make the row dirty again the instant it
      // was marked clean, and the uploader would push the same session forever.
      final updated = DateTime(2026, 8, 3, 12);
      await insert(
        id: 'a',
        endedAt: DateTime(2026, 8, 3, 11),
        updatedAt: updated,
      );

      await queue.markSynced('a', DateTime(2026, 8, 3, 13));

      final row = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals('a'))).getSingle();
      expect(row.updatedAt, updated);
      expect(await queue.dirtyWorkouts(), isEmpty);
    });
  });

  group('isDirty', () {
    test('never uploaded counts as dirty', () async {
      await insert(id: 'a', endedAt: DateTime(2026, 8, 3, 11));
      final row = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals('a'))).getSingle();
      expect(SyncQueue.isDirty(row), isTrue);
    });

    test('a local edit newer than the upload counts as dirty', () async {
      // This is what stops a pull overwriting an edit made seconds ago with
      // the server's copy from yesterday.
      await insert(
        id: 'a',
        endedAt: DateTime(2026, 8, 3, 11),
        syncedAt: DateTime(2026, 8, 3, 12),
        updatedAt: DateTime(2026, 8, 4, 9),
      );
      final row = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals('a'))).getSingle();
      expect(SyncQueue.isDirty(row), isTrue);
    });
  });

  group('the pull watermark', () {
    test('starts unset, so the first pull asks for everything', () async {
      expect(await queue.lastPull(), isNull);
    });

    test('survives being written and read back', () async {
      final at = DateTime(2026, 8, 7, 12, 30);
      await queue.setLastPull(at);
      expect(await queue.lastPull(), at);
    });

    test('is overwritten rather than appended', () async {
      await queue.setLastPull(DateTime(2026, 8, 6));
      await queue.setLastPull(DateTime(2026, 8, 7));
      expect(await queue.lastPull(), DateTime(2026, 8, 7));
      expect(await db.select(db.syncMeta).get(), hasLength(1));
    });
  });
}
