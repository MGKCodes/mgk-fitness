import '../../settings/domain/backup_consent.dart';
import 'run_backup.dart';

/// A [RunBackup] that does nothing until the runner has said yes.
///
/// The gate is a **wrapper rather than a check at each call site**, and that is
/// the whole design. There are already three places a run is pushed from — the
/// recorder on stop, the editor on add, the editor on edit — and the coach will
/// add more when it can log a run from conversation. A rule enforced by
/// remembering is a rule that holds until the next person adds a fourth caller,
/// and the failure mode here is not a bug: it is special-category data leaving
/// a device whose owner declined to send it.
///
/// Wrapping means the unsafe object is unreachable. Nothing outside this file
/// holds the real backup, so there is no path that skips the check.
///
/// Consent is read on **every** call rather than cached at construction. A
/// runner who turns backup off in Settings expects it off for the run they are
/// finishing, not from the next launch.
class ConsentedRunBackup implements RunBackup {
  ConsentedRunBackup({
    required RunBackup inner,
    required BackupConsentStore consent,
  }) : _inner = inner,
       _consent = consent;

  final RunBackup _inner;
  final BackupConsentStore _consent;

  Future<bool> get _allowed async => (await _consent.read()).allowsBackup;

  @override
  Future<bool> pushRun(String runId) async {
    if (!await _allowed) return false;
    return _inner.pushRun(runId);
  }

  @override
  Future<void> pushTrace(String runId) async {
    if (!await _allowed) return;
    await _inner.pushTrace(runId);
  }

  /// Gated like the pushes it is made of: a backfill is a push of many runs
  /// at once, and it is the exact operation a runner who declined would least
  /// want run on their behalf.
  @override
  Future<int> backfill() async {
    if (!await _allowed) return 0;
    return _inner.backfill();
  }

  /// Deletion is **not** gated.
  ///
  /// The others ask "may I send this?"; this one asks "please remove what you
  /// already have", and a runner who has just withdrawn consent is exactly the
  /// person who most needs it to work. Refusing to delete because backup is off
  /// would strand their data in the place they asked it to leave.
  @override
  Future<void> deleteRun(String runId) => _inner.deleteRun(runId);
}
