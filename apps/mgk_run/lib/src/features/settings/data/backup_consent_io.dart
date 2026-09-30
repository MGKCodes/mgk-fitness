import '../domain/backup_consent.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'file_backup_consent.dart';

/// Native (iOS) default: the answer persists to the filesystem, because a
/// consent that forgot itself on relaunch would re-ask the runner every time.
///
/// [owner] is whose training is on the phone, so a yes stops applying while it
/// belongs to somebody else. The app passes the one `main.dart` holds; a caller
/// with none gets a store that reads every phone as unclaimed.
BackupConsentStore createBackupConsentStore({LocalDataOwnerStore? owner}) =>
    FileBackupConsent(owner: owner);
