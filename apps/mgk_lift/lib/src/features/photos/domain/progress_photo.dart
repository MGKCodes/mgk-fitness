import 'package:meta/meta.dart';

/// Which way the lifter was facing.
///
/// **Four fixed poses, not free-form tags.** The whole feature is comparison,
/// and comparison needs the same angle every time — free-form labels produce
/// "front", "Front", "front pose" and three separate one-photo streams that can
/// never be compared with anything. Ported from Liftio, which learned this.
enum Pose {
  front('front', 'Front'),
  rightSide('right_side', 'Right side'),
  back('back', 'Back'),
  leftSide('left_side', 'Left side');

  const Pose(this.stored, this.label);

  /// The value in the database, matching `core.progress_photos.pose_type`.
  final String stored;

  final String label;

  /// Unknown values read as [front] rather than throwing. A photo with a pose
  /// this build does not recognise is still the lifter's photo.
  static Pose fromStored(String? value) => values.firstWhere(
    (p) => p.stored == value,
    orElse: () => Pose.front,
  );

  /// What a new account tracks. Two, not four: the front and back cover most of
  /// what changes visibly, and asking for four every week is how a weekly habit
  /// becomes a chore nobody keeps.
  static const List<Pose> defaults = <Pose>[Pose.front, Pose.back];
}

/// One photo, in one pose, for one week.
@immutable
class ProgressPhoto {
  const ProgressPhoto({
    required this.id,
    required this.weekStart,
    required this.pose,
    required this.path,
    required this.takenAt,
    this.note,
    this.isExcluded = false,
  });

  final String id;

  /// **Monday midnight of the week this belongs to, not when it was taken.**
  ///
  /// Photos are bucketed by week and there is one slot per (week, pose). Daily
  /// granularity sounds more precise and is worse: nothing visible changes in a
  /// day, so a daily log produces hundreds of near-identical frames, and a
  /// comparison over months turns into scrubbing. A week is the shortest
  /// interval over which a change is legible.
  final DateTime weekStart;

  final Pose pose;

  /// Absolute path to the file on this device.
  ///
  /// The local file is the source of truth; the remote copy is backup. That is
  /// the same rule as the rest of the app, and it matters more here — a photo
  /// is not re-creatable from anywhere else.
  final String path;

  final DateTime takenAt;
  final String? note;

  /// Kept, but skipped when playing the sequence back. For the week the lighting
  /// was wrong or the phone was at the wrong height: deleting it loses a record,
  /// and leaving it in makes the comparison jump.
  final bool isExcluded;

  ProgressPhoto copyWith({String? path, String? note, bool? isExcluded}) =>
      ProgressPhoto(
        id: id,
        weekStart: weekStart,
        pose: pose,
        path: path ?? this.path,
        takenAt: takenAt,
        note: note ?? this.note,
        isExcluded: isExcluded ?? this.isExcluded,
      );

  /// The Monday 00:00 of the week containing [date], in local time.
  ///
  /// Deliberately the same rule as the training streak — a photo and a session
  /// taken on the same evening must land in the same week, or Profile tells two
  /// different stories about one Sunday.
  static DateTime weekOf(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }
}

/// A pose and everything shot in it, newest first.
@immutable
class PoseSeries {
  const PoseSeries({required this.pose, required this.photos});

  final Pose pose;

  /// Newest first.
  final List<ProgressPhoto> photos;

  /// The ones a playback would show, oldest first — excluded frames dropped and
  /// the order reversed, because a comparison runs forwards in time even though
  /// the grid reads backwards.
  List<ProgressPhoto> get sequence =>
      photos.where((p) => !p.isExcluded).toList().reversed.toList();

  ProgressPhoto? get latest => photos.isEmpty ? null : photos.first;

  /// Whether this week's photo has been taken. Drives the "2 of 2 done" strip,
  /// which is the only nudge the feature has.
  bool hasPhotoFor(DateTime weekStart) =>
      photos.any((p) => p.weekStart == weekStart);

  /// How many weeks the series spans, counting gaps. `photos.length` would
  /// undercount — someone who shot week 1 and week 12 has eleven weeks of
  /// change, not two.
  int get spanWeeks {
    if (photos.length < 2) return photos.length;
    final oldest = photos.last.weekStart;
    final newest = photos.first.weekStart;
    return (newest.difference(oldest).inDays / 7).round() + 1;
  }
}

/// Where photos are stored and read.
///
/// An interface so the screens can be driven from fakes: a widget test cannot
/// open a camera, and a preview should not need a database.
abstract interface class PhotoLibrary {
  /// Every photo, newest first.
  Future<List<ProgressPhoto>> all();

  /// Saves [sourcePath] into the library for a (week, pose) slot, replacing
  /// whatever was in it. Returns the stored photo.
  Future<ProgressPhoto> put({
    required Pose pose,
    required DateTime weekStart,
    required String sourcePath,
    DateTime? takenAt,
  });

  Future<void> delete(String id);

  Future<void> setExcluded(String id, {required bool excluded});
}

/// Where a new photo comes from.
///
/// Separate from [PhotoLibrary] because a camera is a platform channel and a
/// library is a database — a widget test can fake this one and use a real
/// in-memory version of the other.
abstract interface class PhotoSource {
  /// Opens the camera. Returns the file path, or null if the lifter backed out
  /// or declined the permission — both are ordinary outcomes, not errors.
  Future<String?> capture();

  /// Opens the gallery. Same contract.
  Future<String?> pickFromGallery();
}
