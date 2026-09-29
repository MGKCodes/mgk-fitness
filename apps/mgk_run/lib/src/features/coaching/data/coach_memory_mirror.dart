import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/paged_select.dart';
import '../domain/coach_memory.dart';
import 'coach_memory_store.dart';

/// This app's name in `coach.conversations.app` and `coach.summaries.app`.
///
/// The coach's memory is shared by the suite and partitioned per app by these
/// columns (`20260807130000_coach_memory_per_app`). Every read and write this
/// app makes against them names it: the column default is `run` only because
/// this client once sent nothing, and the migration's own to-do is to drop it
/// once this client names its app -- which it now does.
const String kCoachApp = 'run';

/// Mirrors the coach's memory to the shared Supabase platform (the `runio`
/// schema) so it is not lost with the phone.
///
/// A **mirror, not the source of truth** (CLAUDE.md rule 1). Push-only, never
/// on a read path: [CoachMemoryRepository] calls it after the local write has
/// already committed and treats any failure as a no-op.
///
/// RLS scopes every table to `auth.uid()`, so no query here filters by user —
/// but the rows still carry `user_id`, because the policies check it on write
/// and because it is what enrols these tables in the account-deletion sweep.
class SupabaseCoachMemoryMirror implements CoachMemoryMirror {
  SupabaseCoachMemoryMirror({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  SupabaseQuerySchema get _coach => _client.schema('coach');

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('cannot mirror coach memory while signed out');
    }
    return id;
  }

  @override
  Future<void> pushSummary(CoachSummary summary) async {
    // `(user_id, app)` is the primary key, so this overwrites this app's row
    // and only this app's — the same "replaced, never appended" invariant the
    // local store gets from its constant key.
    await _coach.from('summaries').upsert(<String, dynamic>{
      'user_id': _userId,
      'app': kCoachApp,
      'summary': summary.text,
      'model': summary.model,
      'turns_covered': summary.turnsCovered,
      'updated_at': summary.updatedAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> pushTurn(CoachTurn turn, {required String kind}) async {
    final userId = _userId;

    // `started_at` is deliberately absent from the payload: PostgREST updates
    // only the columns it is given, so an existing conversation keeps the
    // moment it actually began while `last_turn_at` moves forward.
    await _coach.from('conversations').upsert(<String, dynamic>{
      'id': turn.conversationId,
      'user_id': userId,
      'app': kCoachApp,
      'kind': kind,
      'last_turn_at': turn.at.toUtc().toIso8601String(),
    });

    // `ignoreDuplicates` makes this ON CONFLICT DO NOTHING rather than a
    // merging upsert. That is not an optimisation: UPDATE on `coach_turns` is
    // revoked from `authenticated`, so a merging upsert would be rejected. A
    // transcript is append-only, and re-pushing an identical turn is correctly
    // a no-op.
    await _coach.from('turns').upsert(<String, dynamic>{
      'id': turn.remoteId,
      'conversation_id': turn.conversationId,
      'user_id': userId,
      'seq': turn.seq,
      'role': turn.role.wire,
      'body': turn.text,
      'created_at': turn.at.toUtc().toIso8601String(),
    }, ignoreDuplicates: true);
  }

  /// How many conversation ids go into one delete. A few kilobytes of URL,
  /// well inside what PostgREST and every proxy in front of it accept.
  static const int _idsPerDelete = 100;

  @override
  Future<void> pushPrune({required DateTime olderThan}) async {
    // Against a cutoff rather than a list of turn ids, so it is self-healing:
    // a prune that happened while the device was offline is re-applied by the
    // next one instead of leaving the server holding transcript rows the
    // device has already erased.
    //
    // **Only this app's turns.** This was one delete of every `coach.turns`
    // row older than the cutoff, and RLS scopes by person, not by app -- so it
    // took Lift's too. Lift numbers a new turn from the count of its rows, so
    // its memory did not just shrink, it stopped: the next turn collided with
    // one it still had. `turns` has no `app` column (its conversation carries
    // it, deliberately; see the per-app migration), and PostgREST cannot filter
    // a delete through a join, so the conversations are asked for first.
    final conversations = await fetchAllPages(
      (f, t) => _coach
          .from('conversations')
          .select('id')
          .eq('app', kCoachApp)
          .range(f, t),
    );
    final ids = <String>[for (final row in conversations) row['id'] as String];
    final cutoff = olderThan.toUtc().toIso8601String();
    for (var i = 0; i < ids.length; i += _idsPerDelete) {
      await _coach
          .from('turns')
          .delete()
          .inFilter('conversation_id', ids.skip(i).take(_idsPerDelete).toList())
          .lt('created_at', cutoff);
    }
  }
}
