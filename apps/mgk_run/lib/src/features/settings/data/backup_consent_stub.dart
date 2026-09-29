import '../domain/backup_consent.dart';
import '../domain/local_data.dart';

/// Web default (the preview harness only — Runio ships to iOS). No `dart:io`,
/// so the answer lasts the session.
///
/// It starts at [BackupConsent.unknown] rather than granted, which is the safe
/// direction: the harness uploads nothing until something explicitly says yes.
/// [owner] is accepted for the native signature and unused: the harness has no
/// accounts to tell apart.
BackupConsentStore createBackupConsentStore({LocalDataOwnerStore? owner}) =>
    InMemoryBackupConsent();
