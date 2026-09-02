import '../domain/backup_health.dart';

/// Web default (the preview harness only). No `dart:io`, so the record lasts
/// the session — which is all a harness that pushes nothing anywhere needs.
BackupHealthStore createBackupHealthStore() => InMemoryBackupHealth();
