/// The push-only backup seam for runs.
///
/// An interface rather than the Supabase class directly, for the same reason
/// `PlanBackup` is one: the preview harness and the tests must be able to run
/// the whole write path with nothing behind it, and a persona's invented runs
/// must never reach the shared project.
///
/// Every method is best-effort by contract. The caller has already committed
/// locally (CLAUDE.md rule 1), so a failure here costs a backup, never a run.
abstract class RunBackup {
  /// Mirrors the run's summary. Returns true when it landed.
  Future<bool> pushRun(String runId);

  /// Mirrors the run's trace and splits.
  Future<void> pushTrace(String runId);

  /// Removes a run that was deleted locally, so it cannot come back on the
  /// next read.
  Future<void> deleteRun(String runId);

  /// Sends every local run the backup does not already hold, returning how
  /// many went.
  ///
  /// Needed because a run can be stranded in two ordinary ways: it was
  /// recorded before this mirror existed at all, or it was recorded while the
  /// runner had backup switched off. Neither leaves a mark on the row, so the
  /// only honest way to find them is to ask what the server has and compare.
  Future<int> backfill();
}
