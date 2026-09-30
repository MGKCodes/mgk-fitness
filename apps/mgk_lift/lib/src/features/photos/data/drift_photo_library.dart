import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../domain/progress_photo.dart';

/// Photos on disk, with their metadata in the local database.
///
/// **The file is copied into the app's own directory, never referenced where it
/// was found.** A camera capture lands in a cache the OS is free to empty, and a
/// gallery pick returns a URI that may not survive the app being backgrounded.
/// Either way, a row pointing at a file that has quietly disappeared is a photo
/// the lifter cannot get back.
class DriftPhotoLibrary implements PhotoLibrary {
  DriftPhotoLibrary(this._db, {Future<Directory> Function()? directory})
    : _directory = directory ?? _appPhotoDirectory;

  final AppDatabase _db;
  final Future<Directory> Function() _directory;

  /// Ids for new rows. Injected so a test gets predictable ones.
  static String Function() idFactory = () =>
      DateTime.now().microsecondsSinceEpoch.toString();

  static Future<Directory> _appPhotoDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'progress-photos'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<List<ProgressPhoto>> all() async {
    final rows =
        await (_db.select(_db.progressPhotos)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy(<OrderClauseGenerator<$ProgressPhotosTable>>[
                (t) => OrderingTerm.desc(t.weekStart),
              ]))
            .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<ProgressPhoto> put({
    required Pose pose,
    required DateTime weekStart,
    required String sourcePath,
    DateTime? takenAt,
  }) async {
    final dir = await _directory();
    final id = idFactory();
    final stored = File(p.join(dir.path, '$id.jpg'));
    await File(sourcePath).copy(stored.path);

    // Retaking replaces. The slot is the model, so the old row is removed and
    // its file with it — otherwise a week of retakes leaves five orphaned
    // JPEGs on disk that nothing will ever show or clean up.
    final existing =
        await (_db.select(_db.progressPhotos)..where(
              (t) =>
                  t.weekStart.equals(weekStart) &
                  t.poseType.equals(pose.stored) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) await _remove(existing);

    final now = DateTime.now();
    final row = PhotoRow(
      id: id,
      weekStart: weekStart,
      poseType: pose.stored,
      path: stored.path,
      takenAt: takenAt ?? now,
      isExcluded: false,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.progressPhotos).insert(row);
    return _toDomain(row);
  }

  @override
  Future<void> delete(String id) async {
    final row = await (_db.select(
      _db.progressPhotos,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row != null) await _remove(row);
  }

  @override
  Future<void> setExcluded(String id, {required bool excluded}) async {
    await (_db.update(_db.progressPhotos)..where((t) => t.id.equals(id))).write(
      ProgressPhotosCompanion(
        isExcluded: Value(excluded),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Soft-deletes the row and hard-deletes the file.
  ///
  /// Asymmetric on purpose. The row is a tombstone so the delete propagates
  /// rather than the photo reappearing from a backup on the next sync; the file
  /// is gone immediately because "deleted" has to mean deleted for something a
  /// lifter took of their own body.
  Future<void> _remove(PhotoRow row) async {
    final file = File(row.path);
    if (file.existsSync()) {
      await file.delete();
    }
    await (_db.update(
      _db.progressPhotos,
    )..where((t) => t.id.equals(row.id))).write(
      ProgressPhotosCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  ProgressPhoto _toDomain(PhotoRow r) => ProgressPhoto(
    id: r.id,
    weekStart: r.weekStart,
    pose: Pose.fromStored(r.poseType),
    path: r.path,
    takenAt: r.takenAt,
    note: r.note,
    isExcluded: r.isExcluded,
  );
}
