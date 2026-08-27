import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/intro_store.dart';

/// The real [IntroStore]: a marker file in the app support directory.
///
/// A file, not a new dependency and not a database table — the same call
/// `FileDisclaimerStore` makes, for the same reasons. The state is a single bit
/// that must survive relaunch, is never queried in bulk, and belongs to the
/// install rather than the account.
///
/// Imports `dart:io`, so this file must stay out of any import graph that is
/// compiled for web (the preview harness). Reach it through `createIntroStore()`
/// in `intro_store_factory.dart`, never directly.
class FileIntroStore implements IntroStore {
  FileIntroStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  /// Resolves the directory the marker lives in. Injectable so tests can point
  /// it at a temporary directory instead of a real platform path.
  final Future<Directory> Function() _directory;

  static const _fileName = 'intro_completed';

  Future<File> _markerFile() async =>
      File(p.join((await _directory()).path, _fileName));

  /// True only if the marker file is present. Any failure (no permission, no
  /// such directory, platform without a filesystem) reads as *not* done, so the
  /// intro runs again rather than being skipped.
  @override
  Future<bool> isDone() async {
    try {
      return (await _markerFile()).exists();
    } on Object {
      return false;
    }
  }

  /// What the runner said to call them, read back out of the marker.
  ///
  /// Any failure - no file, a file written by an older build that held only a
  /// timestamp, malformed JSON - reads as no name rather than throwing. The
  /// coach simply does not use one, which is exactly what it does for somebody
  /// who skipped the question.
  @override
  Future<String?> readName() async {
    try {
      final file = await _markerFile();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final name = decoded['name'];
      return name is String && name.isNotEmpty ? name : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> markDone({String? name}) async {
    try {
      final file = await _markerFile();
      await file.parent.create(recursive: true);
      // JSON rather than the bare timestamp this used to write, because it has
      // a second thing to carry now. `readName` tolerates the old shape.
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'at': DateTime.now().toUtc().toIso8601String(),
          if (name != null && name.isNotEmpty) 'name': name,
        }),
      );
    } on Object {
      // Nothing to recover: the intro is shown once more next launch, which is
      // the safe direction.
    }
  }
}
