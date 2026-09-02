/// The platform-correct default [BackupHealthStore], chosen at compile time.
///
/// A conditional export so nothing that merely wants to *report* on the backup
/// drags `dart:io` into its import graph. Same shape as
/// `backup_consent_factory.dart`.
library;

export 'backup_health_stub.dart' if (dart.library.io) 'backup_health_io.dart';
