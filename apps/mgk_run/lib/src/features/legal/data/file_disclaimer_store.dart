import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/disclaimer_store.dart';

/// The real [DisclaimerStore]: a marker file in the app support directory.
///
/// A file, not a new dependency and not a database table. The state is a single
/// bit that must survive relaunch, is never queried in bulk, and belongs to the
/// install rather than the account — so the cheapest durable thing wins. Uses
/// `path_provider`, already a dependency of the recording stack.
///
/// Imports `dart:io`, so this file must stay out of any import graph that is
/// compiled for web (the preview harness). Reach it through
/// `createDisclaimerStore()` in `disclaimer_store_factory.dart`, never directly.
class FileDisclaimerStore implements DisclaimerStore {
  FileDisclaimerStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  /// Resolves the directory the marker lives in. Injectable so tests can point
  /// it at a temporary directory instead of a real platform path.
  final Future<Directory> Function() _directory;

  static const _fileName = 'medical_disclaimer_acknowledged';

  Future<File> _markerFile() async =>
      File(p.join((await _directory()).path, _fileName));

  /// True only if the marker file is present. Any failure (no permission, no
  /// such directory, platform without a filesystem) reads as *not*
  /// acknowledged, so the disclaimer is shown again rather than skipped.
  @override
  Future<bool> isAcknowledged() async {
    try {
      return (await _markerFile()).exists();
    } on Object {
      return false;
    }
  }

  @override
  Future<void> acknowledge() async {
    try {
      final file = await _markerFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(DateTime.now().toUtc().toIso8601String());
    } on Object {
      // Nothing to recover: the user is asked again next launch, which is safe.
    }
  }
}
