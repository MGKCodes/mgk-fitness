import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/coach.dart';

/// The coach, via the `coach` Edge Function.
///
/// **There is no model key in this app and there never will be.** The function
/// holds it; this sends a message and the caller's JWT. Everything that costs
/// money — the entitlement check, the rate limit and the spend cap — is decided
/// there, so nothing in this file is worth tampering with.
///
/// The same function serves Run, so a request has to say which surface it is
/// for. `lift_chat` is the only one this app calls, and the function reads which
/// app pays for it from that name rather than from anything sent here.
///
/// Note what is deliberately NOT sent: the training log, the conversation, or
/// what the coach remembers. The function reads all three under this caller's
/// own JWT, so RLS decides what the coach sees, and this app cannot describe a
/// session that did not happen or a sentence nobody said. That is why the
/// request is one line long.
class SupabaseCoach implements CoachService {
  SupabaseCoach(this._client);

  final SupabaseClient _client;

  static const _surface = 'lift_chat';

  /// How long one turn may take before it counts as failed. See
  /// [SupabaseCoachPlanner.requestTimeout] — same reasoning, same number,
  /// deliberately: a chat turn and a plan turn hit the same function.
  static const Duration requestTimeout = Duration(seconds: 90);

  @override
  Future<String> ask(String message) async {
    if (_client.auth.currentUser == null) {
      throw const CoachException(CoachFailure.signedOut);
    }

    try {
      final res = await _client.functions
          .invoke(
            'coach',
            body: <String, Object?>{'surface': _surface, 'message': message},
          )
          // A provider that accepts the connection and then goes quiet would
          // otherwise leave the composer disabled forever, with no error and
          // nothing to retry. The catch-all below already calls this
          // unavailable, which is what it is.
          .timeout(requestTimeout);

      final data = res.data;
      if (data is Map && data['reply'] is String) {
        final reply = data['reply'] as String;
        if (reply.trim().isEmpty) {
          throw const CoachException(CoachFailure.unavailable);
        }
        return reply;
      }
      throw const CoachException(CoachFailure.unavailable);
    } on FunctionException catch (e) {
      throw CoachException(_map(e));
    } on CoachException {
      rethrow;
    } on Object {
      // Sockets, DNS, timeouts. Ordinary in a gym basement and not an error
      // worth dressing up.
      throw const CoachException(CoachFailure.unavailable);
    }
  }

  /// Maps the function's status codes to something the screen can say.
  ///
  /// The codes are the contract, not the bodies — the function deliberately
  /// never forwards an upstream error message, because those can carry our
  /// billing details rather than anything about the lifter.
  ///
  /// 429 covers both a rate limit and the rolling spend cap. They are one thing
  /// to a lifter — come back later — and the function distinguishes them in the
  /// body for when that stops being true.
  static CoachFailure _map(FunctionException e) => switch (e.status) {
    401 => CoachFailure.signedOut,
    402 => CoachFailure.notEntitled,
    429 => CoachFailure.limitReached,
    _ => CoachFailure.unavailable,
  };
}

/// The stored conversation, read directly against `coach.turns`.
///
/// **Not through the Edge Function**, unlike [SupabaseCoach] above — the same
/// split, and the same reasoning, as [SupabaseCoachMemory]. `authenticated`
/// already holds SELECT on `coach.turns` and the `own_turns` policy scopes it
/// to the caller, so this needs nothing the function could add.
///
/// The conversation is addressed rather than looked up. Lift keeps exactly one
/// per person, and the function derives its id the same way — `lift:<user id>`
/// — so finding it costs no round trip. That id is a contract shared with
/// `supabase/functions/coach/coach_memory.ts`; changing it in one place
/// silently orphans every turn written by the other.
class SupabaseCoachTranscript implements CoachTranscript {
  SupabaseCoachTranscript(this._client);

  final SupabaseClient _client;

  static const _app = 'lift';

  /// The window the server replays. **Mirrored from `MEMORY_TURNS` in
  /// `supabase/functions/coach/coach_memory.ts`.** If that number moves and
  /// this does not, the screen starts showing turns the coach has forgotten —
  /// which is the failure this whole feature exists to prevent, wearing the
  /// opposite mask.
  static const int window = 20;

  /// A row read is not a model call. [SupabaseCoach.requestTimeout] is ninety
  /// seconds because a provider may legitimately think for that long; nothing
  /// here may.
  static const Duration requestTimeout = Duration(seconds: 10);

  SupabaseQuerySchema get _coach => _client.schema('coach');

  @override
  Future<List<CoachTurn>> read() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const <CoachTurn>[];

    try {
      // Newest first with a limit, then reversed — the last N turns, which is
      // not what `order(seq)` with a limit returns.
      final rows = await _coach
          .from('turns')
          .select('id, role, body, created_at')
          .eq('conversation_id', '$_app:$userId')
          .order('seq', ascending: false)
          .limit(window)
          .timeout(requestTimeout);

      return _parse(rows).reversed.toList();
    } on Object {
      // Deliberately silent. The composer works without this, and an error
      // banner over a working screen would be the app complaining about its
      // own history rather than helping anyone train.
      return const <CoachTurn>[];
    }
  }

  /// Rows to turns, dropping anything that cannot be attributed.
  ///
  /// Mirrors `parseTurns` in the Edge Function, and for the same reason: a turn
  /// whose speaker is unknown is dropped rather than guessed at. Put it on the
  /// wrong side and the screen shows the coach saying what the lifter said.
  static List<CoachTurn> _parse(List<Map<String, dynamic>> rows) {
    final turns = <CoachTurn>[];
    for (final row in rows) {
      final role = row['role'];
      if (role != 'user' && role != 'assistant') continue;

      final body = (row['body'] as String? ?? '').trim();
      if (body.isEmpty) continue;

      turns.add(
        CoachTurn(
          id: row['id'] as String? ?? 'turn${turns.length}',
          body: body,
          fromCoach: role == 'assistant',
          at:
              DateTime.tryParse(
                row['created_at'] as String? ?? '',
              )?.toLocal() ??
              DateTime.now(),
        ),
      );
    }
    return turns;
  }
}

/// A scripted coach, for tests and the preview harness.
class FakeCoach implements CoachService {
  FakeCoach({
    this.reply = 'Add 2.5kg to your top set next week.',
    this.failWith,
  });

  final String reply;
  final CoachFailure? failWith;

  /// Everything asked of it, in order, so a test can assert what was sent.
  final List<String> asked = <String>[];

  @override
  Future<String> ask(String message) async {
    asked.add(message);
    final failure = failWith;
    if (failure != null) throw CoachException(failure);
    return reply;
  }
}

/// A scripted transcript, for tests and the preview harness.
class FakeCoachTranscript implements CoachTranscript {
  FakeCoachTranscript({List<CoachTurn>? turns, this.empty = false})
    : _turns = turns ?? _sample();

  final List<CoachTurn> _turns;

  /// Reads as a conversation that never happened. The real one answers this way
  /// on a failed read too, so a screen that handles this handles both.
  final bool empty;

  @override
  Future<List<CoachTurn>> read() async => empty ? const <CoachTurn>[] : _turns;

  static List<CoachTurn> _sample() {
    final at = DateTime(2026, 8, 6, 18, 30);
    return <CoachTurn>[
      CoachTurn(
        id: 't1',
        body: 'Why has my bench stalled?',
        fromCoach: false,
        at: at,
      ),
      CoachTurn(
        id: 't2',
        body:
            'You have held 85 kg for six sessions and every top set stopped at '
            'six reps. That is not a plateau, it is a rep target you keep '
            'hitting exactly. Take 80 kg and push for nine.',
        fromCoach: true,
        at: at.add(const Duration(seconds: 20)),
      ),
      CoachTurn(
        id: 't3',
        body: 'Shoulder is sore on the left though',
        fromCoach: false,
        at: at.add(const Duration(minutes: 1)),
      ),
      CoachTurn(
        id: 't4',
        body:
            'Then keep the bar off the sticking point for a fortnight — floor '
            'press instead of flat, same weights. I will keep that in mind.',
        fromCoach: true,
        at: at.add(const Duration(minutes: 1, seconds: 15)),
      ),
    ];
  }
}
