import 'package:supabase_flutter/supabase_flutter.dart';

/// Removes everything the runner has stored in the shared project, without
/// touching their account.
///
/// This is what makes the backup switch honest. A control that stops *future*
/// uploads but leaves years of traces and transcripts sitting on a server is
/// not a withdrawal of consent, it is a pause — and under UK GDPR withdrawing
/// consent has to be as easy as giving it, with the data actually going.
///
/// Distinct from `public.runio_delete_account`, which also removes the login
/// and the shared profile. That is leaving; this is staying with the phone as
/// the only copy.
///
/// **Client-side on purpose.** Every `runio` table has
/// `for all using (user_id = auth.uid())`, and DELETE is granted to
/// `authenticated` — including on `coach_turns`, where UPDATE is revoked but
/// DELETE is deliberately kept for exactly this (see the coach_memory
/// migration). So the runner deletes their own rows with their own token,
/// which needs no privileged function and cannot reach anyone else's data.
/// The seam, so the switch can be tested without a Supabase project.
///
/// Withdrawal deleting nothing is not a bug a widget test can catch through
/// the concrete class: its constructor reaches `Supabase.instance`, so any test
/// touching it needs a live project and is therefore never written. That is how
/// this shipped unwired -- `legal_copy_test.dart` pinned the *words* of the
/// promise in four places while nothing asserted the behaviour at all.
abstract class BackupErasure {
  /// Deletes what the runner has stored. True when it all went.
  Future<bool> eraseAll();
}

class BackupEraser implements BackupErasure {
  BackupEraser({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  SupabaseQuerySchema get _run => _client.schema('run');
  SupabaseQuerySchema get _coach => _client.schema('coach');

  /// Deletes the runner's Run rows. Returns true when it all went.
  ///
  /// Only parents are deleted: `run_points`, `run_splits`, `plan_weeks`,
  /// `plan_sessions` and `turns` all cascade from them. Listing the children as
  /// well would be a second place to forget one.
  ///
  /// The coach is shared by every app in the suite, not owned by Run, but this
  /// switch is the runner asking for their cloud backup to go — and their
  /// conversations are part of that. What it must never do is take a sibling
  /// app's training data, which is why nothing here reaches into `lift`.
  @override
  Future<bool> eraseAll() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      for (final table in const <String>['runs', 'plans', 'runner_profiles']) {
        await _run.from(table).delete().eq('user_id', userId);
      }
      for (final table in const <String>['conversations', 'summaries']) {
        await _coach.from(table).delete().eq('user_id', userId);
      }
      return true;
    } on Object {
      // Reported rather than thrown: the caller has already turned the switch
      // off locally, so uploads have stopped either way. A failed erase must
      // be visible so the runner can try again, not silently successful.
      return false;
    }
  }
}
