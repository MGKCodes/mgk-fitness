import '../domain/progress_photo.dart';

/// A library that keeps everything in memory and copies no files.
///
/// For tests and the preview harness. It is here rather than under `test/`
/// because the preview binary uses it too, and a second near-identical fake is
/// how two versions of "what the library does" start disagreeing.
class InMemoryPhotoLibrary implements PhotoLibrary {
  InMemoryPhotoLibrary([List<ProgressPhoto> seed = const <ProgressPhoto>[]])
    : _photos = List<ProgressPhoto>.of(seed);

  final List<ProgressPhoto> _photos;
  int _counter = 0;

  @override
  Future<List<ProgressPhoto>> all() async {
    final sorted = List<ProgressPhoto>.of(_photos)
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
    return sorted;
  }

  @override
  Future<ProgressPhoto> put({
    required Pose pose,
    required DateTime weekStart,
    required String sourcePath,
    DateTime? takenAt,
  }) async {
    // Same slot rule as the real one: one live photo per week per pose, and
    // putting into an occupied slot replaces.
    _photos.removeWhere((p) => p.pose == pose && p.weekStart == weekStart);
    final photo = ProgressPhoto(
      id: 'photo-${++_counter}',
      weekStart: weekStart,
      pose: pose,
      path: sourcePath,
      takenAt: takenAt ?? weekStart,
    );
    _photos.add(photo);
    return photo;
  }

  @override
  Future<void> delete(String id) async =>
      _photos.removeWhere((p) => p.id == id);

  @override
  Future<void> setExcluded(String id, {required bool excluded}) async {
    final i = _photos.indexWhere((p) => p.id == id);
    if (i == -1) return;
    _photos[i] = _photos[i].copyWith(isExcluded: excluded);
  }
}

/// A source that returns a fixed path without touching a camera.
class FakePhotoSource implements PhotoSource {
  FakePhotoSource(this.path);

  /// Null makes both actions read as "the lifter backed out".
  final String? path;

  @override
  Future<String?> capture() async => path;

  @override
  Future<String?> pickFromGallery() async => path;
}
