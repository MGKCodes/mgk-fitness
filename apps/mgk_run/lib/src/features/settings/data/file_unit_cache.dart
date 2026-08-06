import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:mgk_units/mgk_units.dart';
import '../domain/unit_preference.dart';
import 'unit_cache.dart';

/// The real [UnitCache]: a one-line file in the app support directory holding
/// the same `km`/`mi` text the shared column uses.
///
/// A file rather than a table, for the reasons `FileDisclaimerStore` gives — one
/// short value, never queried in bulk, needs only to survive relaunch. Storing
/// the *shared* vocabulary rather than the enum name means a cache written by
/// one version stays readable by the next.
///
/// Imports `dart:io`, so it must stay out of any web import graph. Reach it via
/// `createUnitCache()` in `unit_cache_factory.dart`, never directly.
class FileUnitCache implements UnitCache {
  FileUnitCache({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const _fileName = 'distance_unit';

  Future<File> _file() async =>
      File(p.join((await _directory()).path, _fileName));

  /// Any failure is a cache miss, so the caller falls through to the server or
  /// to the metric default.
  @override
  Future<UnitSystem?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final text = (await file.readAsString()).trim();
      if (text.isEmpty) return null;
      return UnitPreference.fromStored(text);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(UnitSystem unit) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(unit.storedValue);
    } on Object {
      // Only costs a server round-trip on the next launch.
    }
  }
}
