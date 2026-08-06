import '../domain/backup_consent.dart';

/// Web default (the preview harness only — Runio ships to iOS). No `dart:io`,
/// so the answer lasts the session.
///
/// It starts at [BackupConsent.unknown] rather than granted, which is the safe
/// direction: the harness uploads nothing until something explicitly says yes.
BackupConsentStore createBackupConsentStore() => InMemoryBackupConsent();
