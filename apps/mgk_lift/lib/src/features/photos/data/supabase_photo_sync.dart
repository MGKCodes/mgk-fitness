import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../sync/domain/sync_status.dart';
import '../domain/photo_backup.dart';
import '../domain/progress_photo.dart';

/// Progress photos, to the `progress-photos` bucket and back.
///
/// **The device is the authority, exactly as it is for the training log.** The
/// local file is the copy the app renders from; the bucket is where a second
/// copy lives so a lost phone does not take a year of photographs with it.
/// Nothing here is on the path of taking one.
///
/// ## Two stores, and the order matters
///
/// A photo is a row in `core.progress_photos` and an object in the bucket, and
/// they can disagree. The rule is **object first, row second**, in both
/// directions:
///
/// - Uploading writes the JPEG, then the row. A row whose object is missing is
///   a photo the restore cannot produce and the grid will render as a hole; an
///   object with no row is invisible, costs a few hundred kilobytes, and is
///   swept when the account is deleted. Only one of those is a defect somebody
///   sees.
/// - Deleting removes the row's tombstone *after* the object is gone, for the
///   same reason read the other way: if the delete stops half way, what is left
///   is an orphan rather than a row pointing at nothing.
///
/// ## Deletion is a tombstone, not a disappearance
///
/// `DriftPhotoLibrary` already soft-deletes: the row stays with `deletedAt` set
/// and the file goes immediately. That tombstone is what makes a delete
/// propagate rather than the photo coming back down on the next pull, and it is
/// why this pushes deletions instead of only additions.
///
/// ## What it does not do
///
/// No conflict merge. Two devices shooting the same (week, pose) is the only
/// collision available, the unique index added in
/// `20260901120000_progress_photos_week_start.sql` makes it one row, and last
/// write wins — which is the same call [SupabaseSync] makes and for the same
/// reason: the alternative invents intent from timestamps.
class SupabasePhotoSync implements PhotoBackup {
  SupabasePhotoSync(
    this._db,
    this._client, {
    Future<Directory> Function()? directory,
  }) : _directory = directory ?? _appPhotoDirectory;

  final AppDatabase _db;
  final SupabaseClient _client;
  final Future<Directory> Function() _directory;

  static const String bucket = 'progress-photos';

  /// `core` is not the default schema and is not `public`; PostgREST serves it
  /// only because it is listed under Exposed Schemas. Getting this wrong is a
  /// 404 on every call rather than a compile error.
  SupabaseQuerySchema get _core => _client.schema('core');

  static Future<Directory> _appPhotoDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'progress-photos'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Where a photo lives in the bucket.
  ///
  /// **The user id is the first path segment and the storage policy depends on
  /// it** — `(storage.foldername(name))[1] = auth.uid()` is the whole of the
  /// access control. Changing this shape silently makes every object either
  /// unreachable or, worse, reachable by the wrong person.
  static String objectPath(String userId, String photoId) =>
      '$userId/$photoId.jpg';

  @override
  Future<int> pendingUploads() async => (await _dirty()).length;

  Future<List<PhotoRow>> _dirty() =>
      (_db.select(_db.progressPhotos)..where(
            (t) => t.syncedAt.isNull() | t.updatedAt.isBiggerThan(t.syncedAt),
          ))
          .get();

  @override
  Future<SyncReport> run() async {
    final user = _client.auth.currentUser;
    if (user == null) return const SyncReport.signedOut();

    try {
      final pushed = await _push(user.id);
      final pulled = await _pull(user.id);
      return SyncReport(
        outcome: pushed == 0 && pulled == 0
            ? SyncOutcome.upToDate
            : SyncOutcome.synced,
        pushed: pushed,
        pulled: pulled,
        at: DateTime.now(),
      );
    } on StorageException catch (e) {
      return SyncReport.unavailable('storage: ${e.message}');
    } on PostgrestException catch (e) {
      return SyncReport.unavailable('${e.code}: ${e.message}');
    } on AuthException catch (e) {
      return SyncReport.unavailable(e.message);
    } on Object catch (e) {
      // Sockets, DNS, timeouts. Nothing is lost: the rows stay dirty and the
      // local files are untouched.
      return SyncReport.unavailable(e.toString());
    }
  }

  Future<int> _push(String userId) async {
    final dirty = await _dirty();
    var moved = 0;

    // **Tombstones first, and this is not a preference.**
    //
    // Retaking a week soft-deletes the old row and inserts a new one, so both
    // are dirty and both describe the same slot. `progress_photos_one_per_slot`
    // is a partial unique index over live rows, so pushing the new photo while
    // the old row is still live remotely is rejected — and the rejection takes
    // the whole run with it, leaving the retake permanently unable to upload.
    //
    // Ordering the deletion first makes the slot free before anything claims
    // it. The reverse order fails in a way that looks like a server problem
    // rather than a client one, which is how it would have survived a build.
    for (final row in <PhotoRow>[
      ...dirty.where((r) => r.deletedAt != null),
      ...dirty.where((r) => r.deletedAt == null),
    ]) {
      if (row.deletedAt != null) {
        await _pushDeletion(userId, row);
      } else {
        final sent = await _pushPhoto(userId, row);
        if (!sent) continue;
      }
      await _markSynced(row.id);
      moved++;
    }
    return moved;
  }

  /// Uploads one photo. False when there was nothing to upload.
  Future<bool> _pushPhoto(String userId, PhotoRow row) async {
    final file = File(row.path);
    if (!file.existsSync()) {
      // The row outlived its JPEG — a reinstall, or the OS reclaiming storage.
      // The screen already renders this as "this photo is gone"; there is
      // nothing to send and never will be.
      //
      // **Left dirty on purpose.** Marking it synced would claim a copy exists
      // in the bucket, and the next pull on a new phone would try to download
      // it. One permanently pending row is a truer account than a false one,
      // and `pendingUploads` counting it is the only place anybody sees it.
      return false;
    }

    // Object first. See the class comment: a row without its object is a hole
    // in somebody's grid, an object without its row is a few hundred kilobytes.
    await _client.storage
        .from(bucket)
        .uploadBinary(
          objectPath(userId, row.id),
          await file.readAsBytes(),
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            // Retaking a week replaces the photo under the same id, so the
            // second write has to overwrite rather than 409.
            upsert: true,
          ),
        );

    await _core.from('progress_photos').upsert(<String, Object?>{
      'id': row.id,
      'user_id': userId,
      'date': row.takenAt.millisecondsSinceEpoch,
      'week_start': row.weekStart.millisecondsSinceEpoch,
      'pose_type': row.poseType,
      'note': row.note,
      'storage_path': objectPath(userId, row.id),
      'excluded': row.isExcluded ? 1 : 0,
      'created_at': row.createdAt.millisecondsSinceEpoch,
      'updated_at': row.updatedAt.millisecondsSinceEpoch,
      'deleted_at': null,
    });
    return true;
  }

  Future<void> _pushDeletion(String userId, PhotoRow row) async {
    // Remove the object before the tombstone lands, so a half-finished delete
    // leaves an orphan rather than a row pointing at a file somebody can still
    // reach. `remove` on a missing key is not an error, which is what makes
    // this safe to retry.
    await _client.storage.from(bucket).remove(<String>[
      objectPath(userId, row.id),
    ]);

    await _core.from('progress_photos').upsert(<String, Object?>{
      'id': row.id,
      'user_id': userId,
      'date': row.takenAt.millisecondsSinceEpoch,
      'week_start': row.weekStart.millisecondsSinceEpoch,
      'pose_type': row.poseType,
      'storage_path': objectPath(userId, row.id),
      'excluded': row.isExcluded ? 1 : 0,
      'created_at': row.createdAt.millisecondsSinceEpoch,
      'updated_at': row.updatedAt.millisecondsSinceEpoch,
      'deleted_at': row.deletedAt!.millisecondsSinceEpoch,
    });
  }

  Future<int> _pull(String userId) async {
    final remote = await _core
        .from('progress_photos')
        .select()
        .eq('user_id', userId);

    var applied = 0;
    for (final raw in remote) {
      if (await _applyRemote(raw)) applied++;
    }
    return applied;
  }

  /// Applies one remote row. True when the device changed.
  Future<bool> _applyRemote(Map<String, dynamic> raw) async {
    final id = raw['id'] as String?;
    if (id == null) return false;

    final local = await (_db.select(
      _db.progressPhotos,
    )..where((t) => t.id.equals(id))).getSingleOrNull();

    // A local edit that has not gone up yet wins. Overwriting it with the
    // server's copy would discard something done seconds ago in favour of
    // something done yesterday — the same rule `SyncQueue.isDirty` states for
    // workouts.
    if (local != null &&
        (local.syncedAt == null || local.updatedAt.isAfter(local.syncedAt!))) {
      return false;
    }

    final deletedAt = _time(raw['deleted_at']);
    if (deletedAt != null) {
      if (local == null || local.deletedAt != null) return false;
      // Deleted on another device. Take the file with it: "deleted" has to mean
      // deleted for a photograph somebody took of their own body.
      final file = File(local.path);
      if (file.existsSync()) await file.delete();
      await (_db.update(
        _db.progressPhotos,
      )..where((t) => t.id.equals(id))).write(
        ProgressPhotosCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(deletedAt),
          syncedAt: Value(DateTime.now()),
        ),
      );
      return true;
    }

    final takenAt = _time(raw['date']) ?? DateTime.now();
    // Null `week_start` is a Liftio row, written before the column existed.
    // Derived here rather than in the migration because Monday depends on the
    // timezone the lifter was standing in and the server does not know it.
    final weekStart = _time(raw['week_start']) ?? ProgressPhoto.weekOf(takenAt);
    final updatedAt = _time(raw['updated_at']) ?? takenAt;

    if (local != null && !local.updatedAt.isBefore(updatedAt)) {
      final file = File(local.path);
      if (file.existsSync()) return false;
      // Row is current but the JPEG is gone — a reinstall, or storage
      // reclaimed. This is the case the whole feature exists for, so fall
      // through and fetch it again.
    }

    final path = raw['storage_path'] as String?;
    if (path == null) return false;

    final dir = await _directory();
    final destination = File(p.join(dir.path, '$id.jpg'));
    try {
      await destination.writeAsBytes(
        await _client.storage.from(bucket).download(path),
      );
    } on StorageException {
      // The row promised an object that is not there. One photo missing is not
      // a reason to abandon the rest of somebody's library, so this is skipped
      // rather than thrown — and the row is deliberately not written, so a
      // later run tries again.
      return false;
    }

    await _db
        .into(_db.progressPhotos)
        .insertOnConflictUpdate(
          PhotoRow(
            id: id,
            weekStart: weekStart,
            poseType: raw['pose_type'] as String? ?? Pose.front.stored,
            path: destination.path,
            takenAt: takenAt,
            note: raw['note'] as String?,
            isExcluded: (raw['excluded'] as num? ?? 0) != 0,
            createdAt: _time(raw['created_at']) ?? takenAt,
            updatedAt: updatedAt,
            syncedAt: DateTime.now(),
          ),
        );
    return true;
  }

  Future<void> _markSynced(String id) =>
      (_db.update(_db.progressPhotos)..where((t) => t.id.equals(id))).write(
        // **Not `updatedAt`.** Touching it here would make the row dirty again
        // the instant it was marked clean — a sync that never converges, which
        // `SyncQueue.markSynced` records learning the hard way.
        ProgressPhotosCompanion(syncedAt: Value(DateTime.now())),
      );

  /// Epoch milliseconds from the server, or null.
  ///
  /// The columns are `bigint`, which PostgREST renders as a JSON number; a
  /// value large enough has come back as a double before, so this takes any
  /// [num] rather than casting to [int].
  static DateTime? _time(Object? value) => switch (value) {
    final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
    _ => null,
  };
}
