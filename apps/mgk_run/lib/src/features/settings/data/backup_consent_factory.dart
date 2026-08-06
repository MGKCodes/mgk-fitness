/// The platform-correct default [BackupConsentStore], chosen at compile time.
///
/// A conditional export so nothing that merely needs to *ask* about consent
/// drags `dart:io` into its import graph. Same shape as
/// `unit_cache_factory.dart`.
library;

export 'backup_consent_stub.dart' if (dart.library.io) 'backup_consent_io.dart';
