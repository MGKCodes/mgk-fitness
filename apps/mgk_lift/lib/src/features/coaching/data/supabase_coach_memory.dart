import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/coach_memory.dart';

/// The coach's memory, read and erased directly against `coach.*`.
///
/// **Not through the Edge Function**, unlike everything else the coach does.
/// The function exists to hold a provider key and to gate spending; neither
/// applies to reading a row or deleting one. RLS already scopes both to the
/// caller, and `authenticated` holds exactly the privileges this needs —
/// SELECT on `coach.summaries`, DELETE on it and on `coach.conversations` —
/// so routing it through a function would add a hop and a second place for the
/// scoping to be wrong.
///
/// Everything here is scoped `app = 'lift'`. The schema keys memory per
/// (person, app) precisely so this app cannot read or erase the running
/// coach's half, and forgetting the filter is how that protection is lost.
class SupabaseCoachMemory implements CoachMemoryStore {
  SupabaseCoachMemory(this._client);

  final SupabaseClient _client;

  static const _app = 'lift';

  SupabaseQuerySchema get _coach => _client.schema('coach');

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const CoachMemoryException(CoachMemoryFailure.signedOut);
    }
    return id;
  }

  @override
  Future<CoachMemory> read() async {
    final userId = _userId;
    try {
      final row = await _coach
          .from('summaries')
          .select('summary, updated_at')
          .eq('user_id', userId)
          .eq('app', _app)
          .maybeSingle();

      if (row == null) return CoachMemory.none;
      return CoachMemory(
        summary: (row['summary'] as String? ?? '').trim(),
        updatedAt: DateTime.tryParse(
          row['updated_at'] as String? ?? '',
        )?.toLocal(),
      );
    } on CoachMemoryException {
      rethrow;
    } on Object {
      throw const CoachMemoryException(CoachMemoryFailure.unavailable);
    }
  }

  @override
  Future<void> clear() async {
    final userId = _userId;
    try {
      // The conversations first. `coach.turns` has ON DELETE CASCADE from them,
      // so this takes the transcript with it — and doing it in this order means
      // a failure between the two leaves the memory without its source rather
      // than the source without its memory, which is the direction that
      // regenerates back into existence.
      await _coach
          .from('conversations')
          .delete()
          .eq('user_id', userId)
          .eq('app', _app);

      await _coach
          .from('summaries')
          .delete()
          .eq('user_id', userId)
          .eq('app', _app);
    } on CoachMemoryException {
      rethrow;
    } on Object {
      throw const CoachMemoryException(CoachMemoryFailure.unavailable);
    }
  }
}

/// A scripted memory, for tests and the preview harness.
class FakeCoachMemory implements CoachMemoryStore {
  FakeCoachMemory({CoachMemory? memory, this.failWith})
    : _memory = memory ?? CoachMemory.none;

  CoachMemory _memory;
  final CoachMemoryFailure? failWith;

  bool cleared = false;

  @override
  Future<CoachMemory> read() async {
    final failure = failWith;
    if (failure != null) throw CoachMemoryException(failure);
    return _memory;
  }

  @override
  Future<void> clear() async {
    final failure = failWith;
    if (failure != null) throw CoachMemoryException(failure);
    cleared = true;
    _memory = CoachMemory.none;
  }
}
