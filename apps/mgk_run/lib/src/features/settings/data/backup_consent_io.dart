import '../domain/backup_consent.dart';
import 'file_backup_consent.dart';

/// Native (iOS) default: the answer persists to the filesystem, because a
/// consent that forgot itself on relaunch would re-ask the runner every time.
BackupConsentStore createBackupConsentStore() => FileBackupConsent();
