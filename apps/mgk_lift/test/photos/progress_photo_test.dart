import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/photos/data/drift_photo_library.dart';
import 'package:mgk_lift/src/features/photos/domain/progress_photo.dart';
import 'package:mgk_lift/src/features/stats/domain/training_stats.dart';

void main() {
  group('weeks', () {
    test('a photo is filed under the Monday of its week', () {
      final sunday = DateTime(2026, 8, 9, 22);
      expect(ProgressPhoto.weekOf(sunday), DateTime(2026, 8, 3));
    });

    test('photos and training agree about which week it is', () {
      // A photo and a session on the same Sunday evening must land in the same
      // week, or Profile tells two different stories about one day.
      final evening = DateTime(2026, 8, 9, 21, 30);
      expect(
        ProgressPhoto.weekOf(evening),
        TrainingStats.startOfWeek(evening),
      );
    });
  });

  group('a series', () {
    ProgressPhoto at(int weeksAgo, {bool excluded = false}) => ProgressPhoto(
      id: 'p$weeksAgo',
      weekStart: DateTime(2026, 8, 3).subtract(Duration(days: 7 * weeksAgo)),
      pose: Pose.front,
      path: '/tmp/$weeksAgo.jpg',
      takenAt: DateTime(2026, 8, 3),
      isExcluded: excluded,
    );

    PoseSeries series(List<ProgressPhoto> photos) =>
        PoseSeries(pose: Pose.front, photos: photos);

    test('plays back oldest first, though the grid reads newest first', () {
      final s = series(<ProgressPhoto>[at(0), at(1), at(2)]);
      expect(s.photos.first.id, 'p0');
      expect(s.sequence.first.id, 'p2');
      expect(s.sequence.last.id, 'p0');
    });

    test('excluded frames are kept but not played', () {
      final s = series(<ProgressPhoto>[at(0), at(1, excluded: true), at(2)]);
      expect(s.photos, hasLength(3));
      expect(s.sequence.map((p) => p.id), <String>['p2', 'p0']);
    });

    test('the span counts weeks, not photos', () {
      // Someone who shot week 1 and week 12 has eleven weeks of change, not
      // two. Counting photos would report the gap as no time at all.
      final s = series(<ProgressPhoto>[at(0), at(11)]);
      expect(s.photos, hasLength(2));
      expect(s.spanWeeks, 12);
    });

    test('knows whether this week is done', () {
      final s = series(<ProgressPhoto>[at(1)]);
      expect(s.hasPhotoFor(DateTime(2026, 8, 3)), isFalse);
      expect(s.hasPhotoFor(DateTime(2026, 7, 27)), isTrue);
    });
  });

  group('poses', () {
    test('an unknown pose reads as front rather than throwing', () {
      // A photo shot on a build that knew a pose this one does not is still
      // the lifter's photo.
      expect(Pose.fromStored('side_profile_left'), Pose.front);
      expect(Pose.fromStored(null), Pose.front);
    });

    test('a new account tracks two poses, not four', () {
      expect(Pose.defaults, <Pose>[Pose.front, Pose.back]);
    });
  });

  group('the library on disk', () {
    late AppDatabase db;
    late Directory dir;
    late DriftPhotoLibrary library;
    late File source;
    var counter = 0;

    setUp(() async {
      counter = 0;
      DriftPhotoLibrary.idFactory = () => 'id-${++counter}';
      db = AppDatabase.memory();
      dir = await Directory.systemTemp.createTemp('photo-test');
      library = DriftPhotoLibrary(db, directory: () async => dir);
      source = File('${dir.path}/source.jpg')..writeAsBytesSync(<int>[1, 2, 3]);
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('copies the file in rather than pointing at where it was', () async {
      // A camera capture lands in a cache the OS may empty, and a gallery pick
      // returns a URI that need not survive backgrounding. A row pointing at
      // either is a photo the lifter cannot get back.
      final photo = await library.put(
        pose: Pose.front,
        weekStart: DateTime(2026, 8, 3),
        sourcePath: source.path,
      );

      expect(photo.path, isNot(source.path));
      expect(File(photo.path).existsSync(), isTrue);
      expect(source.existsSync(), isTrue, reason: 'the original is not moved');
    });

    test('one photo per week per pose: retaking replaces', () async {
      final week = DateTime(2026, 8, 3);
      final first = await library.put(
        pose: Pose.front,
        weekStart: week,
        sourcePath: source.path,
      );
      final second = await library.put(
        pose: Pose.front,
        weekStart: week,
        sourcePath: source.path,
      );

      expect(await library.all(), hasLength(1));
      expect((await library.all()).single.id, second.id);
      // And the replaced file goes with it, or a week of retakes leaves
      // orphaned JPEGs nothing will ever show or clean up.
      expect(File(first.path).existsSync(), isFalse);
    });

    test('the same week in a different pose is a different slot', () async {
      final week = DateTime(2026, 8, 3);
      await library.put(
        pose: Pose.front,
        weekStart: week,
        sourcePath: source.path,
      );
      await library.put(
        pose: Pose.back,
        weekStart: week,
        sourcePath: source.path,
      );
      expect(await library.all(), hasLength(2));
    });

    test('deleting removes the file and hides the row', () async {
      final photo = await library.put(
        pose: Pose.front,
        weekStart: DateTime(2026, 8, 3),
        sourcePath: source.path,
      );

      await library.delete(photo.id);

      expect(await library.all(), isEmpty);
      expect(File(photo.path).existsSync(), isFalse);
      // Soft-deleted rather than gone: the row is a tombstone so the delete
      // propagates instead of the photo reappearing from a backup.
      final rows = await db.select(db.progressPhotos).get();
      expect(rows.single.deletedAt, isNotNull);
    });

    test('a deleted slot can be filled again', () async {
      // The unique index is partial on `deleted_at is null`; if it were not,
      // this would fail with a constraint violation.
      final week = DateTime(2026, 8, 3);
      final first = await library.put(
        pose: Pose.front,
        weekStart: week,
        sourcePath: source.path,
      );
      await library.delete(first.id);
      await library.put(
        pose: Pose.front,
        weekStart: week,
        sourcePath: source.path,
      );
      expect(await library.all(), hasLength(1));
    });

    test('excluding keeps the photo and the file', () async {
      final photo = await library.put(
        pose: Pose.front,
        weekStart: DateTime(2026, 8, 3),
        sourcePath: source.path,
      );
      await library.setExcluded(photo.id, excluded: true);

      final stored = (await library.all()).single;
      expect(stored.isExcluded, isTrue);
      expect(File(stored.path).existsSync(), isTrue);
    });
  });
}
