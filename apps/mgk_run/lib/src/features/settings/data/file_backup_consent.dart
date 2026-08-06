import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/backup_consent.dart';

/// The real [BackupConsentStore]: a one-word file in the app support directory.
///
/// A file rather than a table, matching `FileUnitCache` — one short value, never
/// queried in bulk, needs only to survive relaunch. It must also be readable
/// before the database is open, because the first thing a backup asks is
/// whether it is allowed to exist.
///
/// **An unreadable file is a refusal, not a default.** Every failure path here
/// returns [BackupConsent.unknown], which behaves as no. The alternative — a
/// missing file quietly meaning yes — would upload special-category data on the
/// strength of an I/O error, and the runner would have no way to know it had
/// happened.
///
/// Stores the enum's own name rather than a boolean so that "declined" and
/// "never asked" stay distinguishable on disk. Collapsing them would make the
/// app re-ask someone who already said no.
///
/// Imports `dart:io`, so it stays out of any web import graph — reach it
/// through `createBackupConsentStore()`.
class FileBackupConsent implements BackupConsentStore {
  FileBackupConsent({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const _fileName = 'backup_consent';

  Future<File> _file() async =>
      File(p.join((await _directory()).path, _fileName));

  @override
  Future<BackupConsent> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return BackupConsent.unknown;
      final text = (await file.readAsString()).trim();
      return BackupConsent.values.firstWhere(
        (c) => c.name == text,
        orElse: () => BackupConsent.unknown,
      );
    } on Object {
      return BackupConsent.unknown;
    }
  }

  /// A failed write leaves the previous answer standing. That is the safe
  /// direction in both cases: a granted consent that fails to persist reads
  /// back as unknown and asks again, and a withdrawal that fails to persist is
  /// re-applied the next time the runner opens Settings and sees the switch
  /// still on.
  @override
  Future<void> write(BackupConsent consent) async {
    try {
      await (await _file()).writeAsString(consent.name, flush: true);
    } on Object {
      // Deliberate: see above.
    }
  }
}
