import '../domain/backup_health.dart';
import 'file_backup_health.dart';

/// Native (iOS, Android) default: the record persists to the filesystem,
/// because a failure that forgot itself on relaunch would never be seen — the
/// relaunch is exactly when the runner next opens Settings.
BackupHealthStore createBackupHealthStore() => FileBackupHealth();
