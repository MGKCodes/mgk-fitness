import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/coach_memory.dart';
import 'coach_memory_store.dart';

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
    // `user_id` is the primary key, so this overwrites — the same "replaced,
    // never appended" invariant the local store gets from its constant key.
    await _coach.from('summaries').upsert(<String, dynamic>{
      'user_id': _userId,
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

  @override
  Future<void> pushPrune({required DateTime olderThan}) async {
    // One delete against a cutoff rather than a list of ids, so it is
    // self-healing: a prune that happened while the device was offline is
    // re-applied by the next one instead of leaving the server holding
    // transcript rows the device has already erased. RLS scopes it to the
    // caller.
    await _coach
        .from('turns')
        .delete()
        .lt('created_at', olderThan.toUtc().toIso8601String());
  }
}
