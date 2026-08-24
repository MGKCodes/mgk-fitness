import '../../settings/domain/backup_health.dart';
import 'run_backup.dart';

/// A [RunBackup] that writes down what happened.
///
/// Every push in this app is best-effort: the run has already committed
/// locally, so a failed push costs a backup rather than a run (CLAUDE.md rule
/// 1). That is right, and it was implemented as `catch (_) {}` in the recorder
/// and again in the editor — which quietly turned "this cannot fail the caller"
/// into "this cannot be observed by anybody". A push that failed and a push
/// that succeeded left the app in exactly the same state, so a runner could
/// have had backup switched on and working for a week, and switched on and
/// failing for the month after, with nothing anywhere to tell the two apart.
///
/// A **wrapper rather than a report at each call site**, for the reason
/// [ConsentedRunBackup] gives at greater length: runs are pushed from the
/// recorder on stop, the editor on add, the editor on edit and the backfill on
/// launch, and the coach will add more when it can log a run from conversation.
/// A rule that depends on the next caller remembering is a rule with a
/// half-life.
///
/// It sits **inside** the consent gate. A push that consent refused is not a
/// backup that failed — it is a backup the runner declined, and recording it as
/// a failure would put a warning in Settings for a switch working exactly as
/// asked.
class ReportedRunBackup implements RunBackup {
  ReportedRunBackup({
    required RunBackup inner,
    required BackupHealthStore health,
    DateTime Function() now = DateTime.now,
  }) : _inner = inner,
       _health = health,
       _now = now;

  final RunBackup _inner;
  final BackupHealthStore _health;
  final DateTime Function() _now;

  @override
  Future<bool> pushRun(String runId) =>
      // `false` is not an error here but it is still a run that did not land —
      // no signed-in user, or a row that has since gone — and the whole point
      // of this class is that "did not land" has one meaning.
      _watch(() => _inner.pushRun(runId), landed: (bool sent) => sent);

  @override
  Future<void> pushTrace(String runId) => _watch(() => _inner.pushTrace(runId));

  @override
  Future<int> backfill() => _watch(() => _inner.backfill());

  /// Not watched, on purpose.
  ///
  /// This asks the backup to *remove* something rather than to hold it, so a
  /// failure here is not a backup that did not happen — it is a deletion that
  /// did not happen, which is a different problem with a different remedy and
  /// its own surface (`BackupEraser` reports its own failure in Settings).
  /// Folding it in would let a failed delete raise a warning that says the
  /// opposite of what went wrong.
  @override
  Future<void> deleteRun(String runId) => _inner.deleteRun(runId);

  /// Runs [push], records what it did, and changes nothing about what the
  /// caller sees — the result is returned and a throw is rethrown, so this can
  /// be dropped into the chain without altering the contract above or below it.
  Future<T> _watch<T>(
    Future<T> Function() push, {
    bool Function(T result)? landed,
  }) async {
    try {
      final result = await push();
      await _record(succeeded: landed == null || landed(result));
      return result;
    } catch (_) {
      await _record(succeeded: false);
      rethrow;
    }
  }

  Future<void> _record({required bool succeeded}) async {
    final at = _now();
    final current = await _health.read();
    await _health.write(
      succeeded ? current.succeededAt(at) : current.failedAt(at),
    );
  }
}
