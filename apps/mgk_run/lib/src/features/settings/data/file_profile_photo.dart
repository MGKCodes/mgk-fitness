import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/profile_photo.dart';

/// [ProfilePhotoStore] as one file in the app's documents directory.
///
/// Documents rather than cache or temp, which is the whole point: the picker
/// hands back a path inside a cache the system may empty whenever it likes, so
/// referencing that path gives an avatar that disappears on somebody else's
/// schedule. The bytes are copied here, where only this app and its owner can
/// remove them.
///
/// **Nothing syncs this.** See [ProfilePhotoStore] for why that is a rule
/// rather than an omission.
class FileProfilePhoto implements ProfilePhotoStore {
  const FileProfilePhoto({this.directory});

  /// Injected by tests. The real directory otherwise, resolved per call so
  /// constructing this needs no platform channel.
  final Directory? directory;

  static const String _name = 'profile-photo.jpg';

  Future<File?> _file() async {
    try {
      final dir = directory ?? await getApplicationDocumentsDirectory();
      return File(p.join(dir.path, _name));
    } on Object {
      // No documents directory is a platform without one, or a test harness
      // with no channel. An avatar is not worth an exception.
      return null;
    }
  }

  @override
  Future<File?> read() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return null;
      return f;
    } on Object {
      return null;
    }
  }

  @override
  Future<File?> write(File source) async {
    try {
      final dest = await _file();
      if (dest == null) return null;
      await dest.parent.create(recursive: true);
      // Copy, then return — not a rename. The source may sit on a different
      // filesystem from the documents directory, where rename fails.
      final saved = await source.copy(dest.path);
      // The old bytes are gone but Flutter's image cache still holds them
      // under the same path, so a second photo would draw as the first.
      // Cleared by the caller, which owns the widget tree; see AccountScreen.
      return saved;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      final f = await _file();
      if (f != null && await f.exists()) await f.delete();
    } on Object {
      // Nothing to do about it, and nothing depends on it: `read` checks
      // existence rather than trusting a flag.
    }
  }
}
