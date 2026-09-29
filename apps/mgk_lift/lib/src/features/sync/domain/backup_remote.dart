/// The server half of backup: where a workout is sent, and where changes are
/// read back from.
///
/// Split from the uploader so the part that decides what is safe — which rows
/// go, what a refusal does to the queue, what a pull may overwrite — can be
/// tested against a fake, with no network and no Supabase client. The
/// Supabase implementation is the only code that sees the client's own
/// exceptions; everything it throws is a `BackupFailure`.
abstract interface class BackupRemote {
  /// The signed-in account, or null when there is none — which is not a
  /// failure: tracking works signed out.
  String? get userId;

  /// Saves one workout, whole: the row, its movements and their sets, as one
  /// write. Replaces whatever the server held for it.
  ///
  /// Throws `BackupFailure`.
  Future<void> save(Map<String, Object?> workout);

  /// Every workout of this account changed after [since] — all of them when
  /// null — each with its `exercises` and their `sets`, oldest change first.
  ///
  /// Throws `BackupFailure`.
  Future<List<Map<String, dynamic>>> changedSince(DateTime? since);
}
