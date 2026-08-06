import '../../settings/domain/backup_consent.dart';
import '../domain/coach_memory.dart';
import '../domain/session_status.dart';
import '../domain/stored_plan.dart';
import '../domain/training_plan.dart';
import 'coach_memory_store.dart';
import 'plan_store.dart';

/// Consent gates for the plan backup and the coach's memory mirror.
///
/// Both wrappers, for the reason set out on [ConsentedRunBackup]: a rule
/// enforced by remembering to check holds only until the next caller is added,
/// and what escapes here is special-category data (CLAUDE.md rule 6). Wrapping
/// makes the ungated object unreachable rather than merely unused.
///
/// The transcript mirror is the one that matters most. A plan is derived from
/// health data; a transcript **is** health data, in the runner's own sentences
/// about their own body — "my calf has been sore since the half". If only one
/// of the three backups were ever gated it should have been this one, and it
/// was the last to be.

/// A [PlanBackup] that does nothing until the runner has agreed.
class ConsentedPlanBackup implements PlanBackup {
  ConsentedPlanBackup({
    required PlanBackup inner,
    required BackupConsentStore consent,
  }) : _inner = inner,
       _consent = consent;

  final PlanBackup _inner;
  final BackupConsentStore _consent;

  Future<bool> get _allowed async => (await _consent.read()).allowsBackup;

  @override
  Future<void> pushPlan(StoredPlan plan) async {
    if (await _allowed) await _inner.pushPlan(plan);
  }

  @override
  Future<void> pushWeek(StoredPlan plan, TrainingWeek week) async {
    if (await _allowed) await _inner.pushWeek(plan, week);
  }

  @override
  Future<void> pushStatus({
    required StoredPlan plan,
    required int weekIndex,
    required int weekday,
    required DateTime date,
    required SessionStatus status,
  }) async {
    if (!await _allowed) return;
    await _inner.pushStatus(
      plan: plan,
      weekIndex: weekIndex,
      weekday: weekday,
      date: date,
      status: status,
    );
  }
}

/// A [CoachMemoryMirror] that does nothing until the runner has agreed.
class ConsentedMemoryMirror implements CoachMemoryMirror {
  ConsentedMemoryMirror({
    required CoachMemoryMirror inner,
    required BackupConsentStore consent,
  }) : _inner = inner,
       _consent = consent;

  final CoachMemoryMirror _inner;
  final BackupConsentStore _consent;

  Future<bool> get _allowed async => (await _consent.read()).allowsBackup;

  @override
  Future<void> pushSummary(CoachSummary summary) async {
    if (await _allowed) await _inner.pushSummary(summary);
  }

  @override
  Future<void> pushTurn(CoachTurn turn, {required String kind}) async {
    if (await _allowed) await _inner.pushTurn(turn, kind: kind);
  }

  /// Pruning is **not** gated, for the same reason deleting a run is not.
  ///
  /// It only ever removes rows, and it is expressed as "delete everything older
  /// than this", so running it without consent cannot send anything and can
  /// only shrink what is already stored. A runner who has just withdrawn
  /// consent is the person whose old transcripts most need clearing out.
  @override
  Future<void> pushPrune({required DateTime olderThan}) =>
      _inner.pushPrune(olderThan: olderThan);
}
