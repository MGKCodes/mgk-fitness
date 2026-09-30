import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/photos/data/supabase_photo_sync.dart';
import 'package:mgk_lift/src/features/photos/domain/progress_photo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The half of photo sync that can be proved without a server.
///
/// The upload itself needs Supabase and a real bucket, so it is exercised on a
/// device against the live project. What is here is the part that decides
/// **which** photos go and **where** they land — the rules that, if wrong, lose
/// somebody's photographs or hand them to the wrong account. Those should not
/// need a network to check, for the same reason `SyncQueue` was split out.
void main() {
  late AppDatabase db;
  var slot = 0;

  setUp(() {
    db = AppDatabase.memory();
    slot = 0;
  });
  tearDown(() async => db.close());

  Future<void> insert({
    required String id,
    DateTime? syncedAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    DateTime? week,
  }) {
    final at = updatedAt ?? DateTime(2026, 8, 10);
    return db
        .into(db.progressPhotos)
        .insert(
          ProgressPhotosCompanion.insert(
            id: id,
            // A week of its own per photo. Every one used to share a slot,
            // which the database forbids — two live photos of one pose in one
            // week — and this passed only because a fresh install never got
            // the index that says so. The dirty rule reads `updatedAt`, which
            // is left exactly as each test sets it.
            weekStart:
                week ??
                ProgressPhoto.weekOf(at).add(Duration(days: 7 * slot++)),
            poseType: Pose.front.stored,
            path: '/photos/$id.jpg',
            takenAt: at,
            updatedAt: Value(at),
            createdAt: Value(at),
            deletedAt: Value(deletedAt),
            syncedAt: Value(syncedAt),
          ),
        );
  }

  /// Reaches the private dirty rule the only way a test should: through the
  /// count the screen shows.
  Future<int> pending() => SupabasePhotoSync(db, _NoClient()).pendingUploads();

  group('where a photo lands in the bucket', () {
    test('is the user id, then the photo id', () {
      // **The storage policy is `(storage.foldername(name))[1] = auth.uid()`
      // and nothing else.** This shape IS the access control, so a change here
      // makes every object either unreachable or reachable by the wrong
      // person, with no error either way.
      expect(
        SupabasePhotoSync.objectPath('user-1', 'photo-9'),
        'user-1/photo-9.jpg',
      );
    });

    test('never puts a photo outside its owner folder', () {
      // The failure this guards is a path that starts with anything but the
      // user id — a shared prefix, a pose name, a date bucket. Any of those
      // would be readable by every signed-in account in the project.
      const userId = 'abc-123';
      final path = SupabasePhotoSync.objectPath(userId, 'p1');

      expect(path.startsWith('$userId/'), isTrue);
      expect(path.split('/').first, userId);
      expect(path.split('/'), hasLength(2));
    });
  });

  group('what counts as waiting to upload', () {
    test('a photo that has never been uploaded', () async {
      await insert(id: 'p1');
      expect(await pending(), 1);
    });

    test('an edit made since the last upload', () async {
      await insert(
        id: 'p1',
        syncedAt: DateTime(2026, 8, 10),
        updatedAt: DateTime(2026, 8, 11),
      );
      expect(await pending(), 1);
    });

    test('but not one that has not changed since', () async {
      await insert(
        id: 'p1',
        updatedAt: DateTime(2026, 8, 10),
        syncedAt: DateTime(2026, 8, 11),
      );
      expect(await pending(), 0);
    });

    test('a deletion is waiting too, not finished', () async {
      // The tombstone is the whole mechanism: without pushing it, a photo
      // deleted on this phone comes straight back down on the next pull. A
      // delete that undoes itself is worse than one that fails.
      await insert(
        id: 'p1',
        syncedAt: DateTime(2026, 8, 10),
        updatedAt: DateTime(2026, 8, 12),
        deletedAt: DateTime(2026, 8, 12),
      );
      expect(await pending(), 1);
    });

    test('every existing photo is pending the first time this runs', () async {
      // `syncedAt` was added by schema 6 and is null on every row that already
      // existed, which is exactly right — nothing has ever been uploaded, so a
      // lifter's whole library goes up on the first sync rather than only the
      // photos they take from now on.
      await insert(id: 'p1');
      await insert(id: 'p2');
      await insert(id: 'p3');

      expect(await pending(), 3);
    });
  });

  group('the order a retake goes up in', () {
    test('the tombstone and its replacement are both waiting', () async {
      // A retake is two rows describing one slot: the old one soft-deleted,
      // the new one fresh. Both dirty, and the order they go up in decides
      // whether the upload succeeds at all — `progress_photos_one_per_slot` is
      // a partial unique index over live rows, so the replacement is rejected
      // while the original is still live on the server.
      //
      // This test pins the shape the ordering rule depends on. The ordering
      // itself lives in `_push`, which needs a bucket to exercise.
      final week = ProgressPhoto.weekOf(DateTime(2026, 8, 10));
      await insert(
        id: 'old',
        syncedAt: DateTime(2026, 8, 10),
        updatedAt: DateTime(2026, 8, 12),
        deletedAt: DateTime(2026, 8, 12),
        week: week,
      );
      // The one fixture here that shares a slot on purpose, and a legal one:
      // the slot index covers live rows only, and the original is a tombstone.
      await insert(id: 'new', updatedAt: DateTime(2026, 8, 12), week: week);

      expect(await pending(), 2);

      final rows = await db.select(db.progressPhotos).get();
      expect(rows.where((r) => r.deletedAt != null), hasLength(1));
      expect(rows.where((r) => r.deletedAt == null), hasLength(1));
      // Same slot, which is what makes the order matter.
      expect(rows.every((r) => r.weekStart == week), isTrue);
      expect(rows.map((r) => r.poseType).toSet(), <String>{Pose.front.stored});
    });
  });

  group('the week a photo is filed under', () {
    test('is Monday, in the local zone', () {
      // The reason `week_start` is its own column rather than derived on the
      // server: Monday depends on where the lifter was standing, and the
      // server does not know. Same rule as the training streak, so a photo and
      // a session from one Sunday evening land in the same week.
      final sunday = DateTime(2026, 8, 9, 21, 30);
      final monday = DateTime(2026, 8, 10, 6, 0);

      expect(ProgressPhoto.weekOf(sunday), DateTime(2026, 8, 3));
      expect(ProgressPhoto.weekOf(monday), DateTime(2026, 8, 10));
    });
  });
}

/// Stands in for a client that is never reached.
///
/// Every test here stops before the network: `pendingUploads` reads the local
/// database and returns. Passing a real client would need Supabase initialised
/// for a code path that does not touch it.
class _NoClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('the network is not part of this test');
}
