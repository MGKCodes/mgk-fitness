/// What became of the last attempt to send something to the backup.
///
/// A push is best-effort by contract — the run has already committed locally,
/// so a failure costs a backup and never a run (CLAUDE.md rule 1). For a long
/// time "best-effort" was implemented as `catch (_) {}` and nothing else, which
/// is a different thing: a backup that did not happen and nobody was told. A
/// runner who believes their runs are mirrored, and whose pushes have been
/// failing for a month, finds out when they lose the phone.
///
/// So the outcome is recorded. Not shouted about — there is nothing for the
/// runner to do mid-run about a failed upload, and a toast over a finished run
/// would be the app apologising for something that cost them nothing — but kept
/// somewhere honest, next to the switch that promised the backup in the first
/// place.
///
/// **What this does and does not claim.** It reports the *last attempt*. It
/// does not, and cannot, say whether everything on the phone is mirrored: the
/// only thing that can answer that is the backfill, which asks the server what
/// it already holds and sends the difference. That runs on every launch, which
/// is also why a failure here is worth reporting but not worth alarming about —
/// it is usually repaired before the runner has looked.
class BackupHealth {
  const BackupHealth({this.lastSucceededAt, this.lastFailedAt});

  /// When something last reached the backup. Null means nothing ever has, which
  /// is the ordinary state of a phone whose owner declined, or has not yet run.
  final DateTime? lastSucceededAt;

  /// When a push last failed. Null means none has, not that all is well —
  /// a runner who has never been online has neither.
  final DateTime? lastFailedAt;

  /// True when the most recent attempt was the failed one.
  ///
  /// Deliberately last-attempt-wins rather than sticky. A later success does
  /// not prove the earlier failure was repaired, but it does prove the backup
  /// is reachable, and leaving the warning up after that would make it
  /// permanent furniture — which is how a warning stops being read.
  bool get isFailing {
    final failed = lastFailedAt;
    if (failed == null) return false;
    final succeeded = lastSucceededAt;
    return succeeded == null || failed.isAfter(succeeded);
  }

  /// This record with a success at [at]. Any earlier failure is kept, so the
  /// two timestamps stay a small history rather than a single flag.
  BackupHealth succeededAt(DateTime at) =>
      BackupHealth(lastSucceededAt: at, lastFailedAt: lastFailedAt);

  /// This record with a failure at [at].
  BackupHealth failedAt(DateTime at) =>
      BackupHealth(lastSucceededAt: lastSucceededAt, lastFailedAt: at);
}

/// Where the record is kept.
///
/// Local only, like `BackupConsentStore` and for a sharper version of the same
/// reason: this is a note about the backup failing, and the one place it
/// certainly cannot be written is the backup.
abstract class BackupHealthStore {
  Future<BackupHealth> read();

  Future<void> write(BackupHealth health);
}

/// An in-memory store, for tests and the preview harness.
class InMemoryBackupHealth implements BackupHealthStore {
  InMemoryBackupHealth([this._value = const BackupHealth()]);

  BackupHealth _value;

  @override
  Future<BackupHealth> read() async => _value;

  @override
  Future<void> write(BackupHealth health) async => _value = health;
}
