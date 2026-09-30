import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/sync/data/sync_queue.dart';

void main() {
  late AppDatabase db;
  late SyncQueue queue;
  var clock = DateTime(2026, 8, 5);

  setUp(() {
    clock = DateTime(2026, 8, 5);
    db = AppDatabase.memory();
    queue = SyncQueue(db, clock: () => clock);
  });

  tearDown(() async => db.close());

  Future<void> insert({
    required String id,
    DateTime? endedAt,
    DateTime? syncedAt,
    DateTime? updatedAt,
    bool isTemplate = false,
    DateTime? deletedAt,
  }) => db
      .into(db.workouts)
      .insert(
        WorkoutsCompanion.insert(
          id: id,
          name: 'Session $id',
          startedAt: DateTime(2026, 8, 3),
          endedAt: Value(endedAt),
          syncedAt: Value(syncedAt),
          isTemplate: Value(isTemplate),
          deletedAt: Value(deletedAt),
          updatedAt: Value(updatedAt ?? DateTime(2026, 8, 3, 12)),
        ),
      );

  Future<WorkoutRow> row(String id) =>
      (db.select(db.workouts)..where((w) => w.id.equals(id))).getSingle();

  Future<void> edit(String id, DateTime at) =>
      (db.update(db.workouts)..where((w) => w.id.equals(id))).write(
        WorkoutsCompanion(updatedAt: Value(at)),
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

    test(
      'a saved workout goes up too, so the library survives the phone',
      () async {
        // It never ended and never will; it goes up as a template.
        await insert(id: 't', isTemplate: true);
        expect((await queue.dirtyWorkouts()).single.id, 't');
      },
    );

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

    test('a delete of something uploaded goes up as a tombstone', () async {
      await insert(
        id: 't',
        isTemplate: true,
        syncedAt: DateTime(2026, 8, 3, 13),
        deletedAt: DateTime(2026, 8, 4),
        updatedAt: DateTime(2026, 8, 4),
      );
      expect((await queue.dirtyWorkouts()).single.deletedAt, isNotNull);
    });

    test('a delete of something never uploaded goes nowhere', () async {
      // The server never had it; there is nothing to tell it.
      await insert(
        id: 't',
        isTemplate: true,
        deletedAt: DateTime(2026, 8, 4),
        updatedAt: DateTime(2026, 8, 4),
      );
      expect(await queue.dirtyWorkouts(), isEmpty);
      expect((await queue.pending()).workouts, 0);
    });

    test('oldest change first', () async {
      await insert(
        id: 'new',
        endedAt: DateTime(2026, 8, 3),
        updatedAt: DateTime(2026, 8, 4),
      );
      await insert(
        id: 'old',
        endedAt: DateTime(2026, 8, 3),
        updatedAt: DateTime(2026, 8, 3),
      );
      expect((await queue.dirtyWorkouts()).map((w) => w.id), <String>[
        'old',
        'new',
      ]);
    });
  });

  group('a refused workout', () {
    test('waits for an edit instead of blocking every run', () async {
      await insert(id: 'bad', endedAt: DateTime(2026, 8, 3, 11));
      await insert(id: 'good', endedAt: DateTime(2026, 8, 3, 11));

      await queue.markRejected('bad', '22003: numeric field overflow');

      expect((await queue.dirtyWorkouts()).map((w) => w.id), <String>['good']);
      final pending = await queue.pending();
      expect(pending.workouts, 1);
      expect(pending.rejected.single.id, 'bad');
      expect(pending.rejected.single.name, 'Session bad');
      expect(pending.rejected.single.detail, startsWith('22003'));
      expect(pending.isBackedUp('bad'), isFalse);
    });

    test('is tried again once it is edited', () async {
      await insert(id: 'bad', endedAt: DateTime(2026, 8, 3, 11));
      await queue.markRejected('bad', '23514: check');

      clock = DateTime(2026, 8, 6);
      await edit('bad', DateTime(2026, 8, 7));

      expect((await queue.dirtyWorkouts()).single.id, 'bad');
      expect((await queue.pending()).rejected, isEmpty);
    });

    test('counts its attempts, and never touches updatedAt', () async {
      await insert(id: 'bad', endedAt: DateTime(2026, 8, 3, 11));
      await queue.markRejected('bad', '23514: check');
      await queue.markRejected('bad', '23514: check');
      final r = await row('bad');
      expect(r.syncAttempts, 2);
      expect(r.updatedAt, DateTime(2026, 8, 3, 12));
    });

    test('a failure that was not the row clears an old refusal', () async {
      // Edited after a refusal, then caught by a dropped connection: without
      // the clear, the stale refusal and the new attempt time would take it
      // back out of the queue.
      await insert(id: 'a', endedAt: DateTime(2026, 8, 3, 11));
      await queue.markRejected('a', '23514: check');
      clock = DateTime(2026, 8, 6);
      await edit('a', DateTime(2026, 8, 7));

      clock = DateTime(2026, 8, 8);
      await queue.markAttempt('a');

      expect((await queue.dirtyWorkouts()).single.id, 'a');
      expect((await row('a')).syncError, isNull);
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

      await queue.markSynced('a', updated);

      final r = await row('a');
      expect(r.updatedAt, updated);
      expect(await queue.dirtyWorkouts(), isEmpty);
    });

    test(
      'marks the copy that went, so an edit in flight stays dirty',
      () async {
        // Stamped "now", this marked an edit made during the upload as sent.
        final sent = DateTime(2026, 8, 3, 12);
        await insert(
          id: 'a',
          endedAt: DateTime(2026, 8, 3, 11),
          updatedAt: sent,
        );
        await edit('a', DateTime(2026, 8, 3, 12, 0, 5));

        await queue.markSynced('a', sent);

        expect((await queue.dirtyWorkouts()).single.id, 'a');
      },
    );

    test('clears any refusal and the attempt count', () async {
      await insert(id: 'a', endedAt: DateTime(2026, 8, 3, 11));
      await queue.markRejected('a', '23514: check');
      await queue.markSynced('a', DateTime(2026, 8, 3, 12));
      final r = await row('a');
      expect(r.syncError, isNull);
      expect(r.syncAttempts, 0);
    });
  });

  group('isDirty', () {
    test('never uploaded counts as dirty', () async {
      await insert(id: 'a', endedAt: DateTime(2026, 8, 3, 11));
      expect(SyncQueue.isDirty(await row('a')), isTrue);
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
      expect(SyncQueue.isDirty(await row('a')), isTrue);
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
