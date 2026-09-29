import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/local_data.dart';

/// The real [LocalDataOwnerStore]: one user id in a file beside the backup
/// answer.
///
/// A file for the reasons every other small store here is one — a single
/// value, never queried, needed before the database is open — and **not a
/// column**, because the question is about the phone rather than about any row
/// on it, and a column would be a schema change on every table to answer it.
///
/// Written through a temporary file and a rename, so a crash mid-write leaves
/// the previous owner rather than half an id. An owner nobody can read is
/// treated as no owner, which is what every other store here does with a file
/// it cannot read; the rename is what makes that case close to impossible.
///
/// Imports `dart:io`, so it stays out of any web import graph; `main.dart`
/// constructs it directly, as it does the database.
class FileLocalDataOwner implements LocalDataOwnerStore {
  FileLocalDataOwner({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const _fileName = 'local_data_owner';

  Future<File> _file() async =>
      File(p.join((await _directory()).path, _fileName));

  @override
  Future<String?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final id = (await file.readAsString()).trim();
      return id.isEmpty ? null : id;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String userId) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final pending = File('${file.path}.tmp');
      await pending.writeAsString(userId, flush: true);
      await pending.rename(file.path);
    } on Object {
      // Nothing to recover: the next sign-in asks again, and the answer for a
      // phone with training on it and no owner is to let the account claim it.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } on Object {
      // Nothing depends on it: an owner of a phone with no training on it is
      // replaced by the next account to sign in.
    }
  }
}
