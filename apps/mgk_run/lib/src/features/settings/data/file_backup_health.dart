import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/backup_health.dart';

/// The real [BackupHealthStore]: two timestamps in a small file beside the
/// consent answer.
///
/// A file rather than a table, matching `FileBackupConsent` and
/// `FileUnitCache` — a couple of short values, never queried in bulk, that need
/// only survive relaunch. It also has to be writable from the push path, which
/// runs the moment a run is finalised, and reaching for the database there
/// would put a second write in front of the one that matters.
///
/// **An unreadable file reports nothing rather than reporting health.** Every
/// failure path returns an empty [BackupHealth], which Settings renders as "not
/// backed up yet". The alternative — treating an I/O error as a success — would
/// tell a runner their data was safe on the strength of a failed read, which is
/// the one answer this file must never give.
///
/// Imports `dart:io`, so it stays out of any web import graph — reach it
/// through `createBackupHealthStore()`.
class FileBackupHealth implements BackupHealthStore {
  FileBackupHealth({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const _fileName = 'backup_health.json';

  Future<File> _file() async =>
      File(p.join((await _directory()).path, _fileName));

  @override
  Future<BackupHealth> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const BackupHealth();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return const BackupHealth();
      return BackupHealth(
        lastSucceededAt: _at(decoded['succeeded_at']),
        lastFailedAt: _at(decoded['failed_at']),
      );
    } on Object {
      return const BackupHealth();
    }
  }

  /// A failed write leaves the previous record standing, which is the safe
  /// direction: this file exists to report a problem, and a report that cannot
  /// be written is not a reason to erase the last one that could.
  @override
  Future<void> write(BackupHealth health) async {
    try {
      await (await _file()).writeAsString(
        jsonEncode(<String, String?>{
          'succeeded_at': health.lastSucceededAt?.toIso8601String(),
          'failed_at': health.lastFailedAt?.toIso8601String(),
        }),
        flush: true,
      );
    } on Object {
      // Deliberate: see above.
    }
  }

  /// A stored timestamp, or null for anything that is not one — a truncated
  /// write, or a field this version does not understand.
  static DateTime? _at(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
