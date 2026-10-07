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
  Future<String> ask(String message, {required String conversationId}) async {
    if (_client.auth.currentUser == null) {
      throw const CoachException(CoachFailure.signedOut);
    }

    try {
      final res = await _client.functions
          .invoke(
            'coach',
            body: <String, Object?>{
              'surface': _surface,
              'message': message,
              'conversation': conversationId,
            },
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
  ///
  /// Any other status means the function answered, so it is the server's
  /// fault, not the signal's. Only no answer at all is [CoachFailure.unavailable].
  static CoachFailure _map(FunctionException e) => switch (e.status) {
    401 => CoachFailure.signedOut,
    402 => CoachFailure.notEntitled,
    429 => CoachFailure.limitReached,
    _ => CoachFailure.serverError,
  };
}

/// The stored conversation, read directly against `coach.turns`.
///
/// **Not through the Edge Function**, unlike [SupabaseCoach] above — the same
/// split, and the same reasoning, as [SupabaseCoachMemory]. `authenticated`
/// already holds SELECT on `coach.turns` and the `own_turns` policy scopes it
/// to the caller, so this needs nothing the function could add.
///
/// **The conversation id is the client's, and it is a session** (ADR-0002).
/// This app used to address one conversation per person as `lift:<user id>`,
/// computed rather than fetched, and the Edge Function derived the same string
/// — so every turn ever said sat in one endless transcript and the last twenty
/// of them were replayed to the model undated. That is how a month-old sentence
/// gets read as this morning's.
///
/// Now the id is generated per session, sent with every turn, and the function
/// uses what it is given rather than deriving anything. The derivation is
/// deleted rather than kept beside this: two ways to answer "which
/// conversation?" is how the wrong one gets reached for again.
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
  Future<List<CoachTurn>> read(String conversationId) async {
    if (_client.auth.currentUser == null) return const <CoachTurn>[];

    try {
      // Newest first with a limit, then reversed — the last N turns, which is
      // not what `order(seq)` with a limit returns.
      final rows = await _coach
          .from('turns')
          .select('id, role, body, created_at')
          .eq('conversation_id', conversationId)
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

  @override
  Future<String?> openConversationId({
    Duration window = coachSessionWindow,
  }) async {
    if (_client.auth.currentUser == null) return null;

    try {
      // One row: the most recent turn there is. Whether a conversation is still
      // open is a question about when it was last spoken in, and that is the
      // row that answers it. RLS scopes this to the caller, so no filter here
      // is doing security work.
      final rows = await _coach
          .from('turns')
          .select('conversation_id, created_at')
          .order('created_at', ascending: false)
          .limit(1)
          .timeout(requestTimeout);

      if (rows.isEmpty) return null;
      final at = DateTime.tryParse(rows.first['created_at'] as String? ?? '');
      if (at == null) return null;
      if (DateTime.now().difference(at.toLocal()) > window) return null;
      return rows.first['conversation_id'] as String?;
    } on Object {
      // A session that cannot be established is a new one, which is the safe
      // direction: the cost is a coach re-establishing context it had, and the
      // cost of the other direction is the bug this exists to prevent.
      return null;
    }
  }

  @override
  Future<List<CoachTurn>> fullTranscript(String conversationId) async {
    if (_client.auth.currentUser == null) return const <CoachTurn>[];

    try {
      // Ascending with no limit: this is a conversation that has ended, so
      // "all of it" is bounded by how long somebody talked rather than by
      // anything that keeps growing.
      final rows = await _coach
          .from('turns')
          .select('id, role, body, created_at')
          .eq('conversation_id', conversationId)
          .order('seq', ascending: true)
          .timeout(requestTimeout);

      return _parse(rows);
    } on Object {
      return const <CoachTurn>[];
    }
  }

  @override
  Future<List<CoachConversationSummary>> conversations({int limit = 20}) async {
    if (_client.auth.currentUser == null) {
      return const <CoachConversationSummary>[];
    }

    try {
      final rows = await _coach
          .from('conversations')
          .select('id, started_at, last_turn_at')
          .eq('app', _app)
          .order('last_turn_at', ascending: false)
          .limit(limit)
          .timeout(requestTimeout);

      final summaries = <CoachConversationSummary>[];
      for (final row in rows) {
        final id = row['id'] as String?;
        if (id == null) continue;
        final last = DateTime.tryParse(row['last_turn_at'] as String? ?? '');
        if (last == null) continue;
        final started =
            DateTime.tryParse(row['started_at'] as String? ?? '') ?? last;

        // The opening line and the count come from the turns, because
        // `coach.conversations` stores neither. One read per conversation is
        // affordable at this limit, and it is what makes the list recognisable
        // rather than a column of dates.
        final turns = await _coach
            .from('turns')
            .select('id, role, body, created_at')
            .eq('conversation_id', id)
            .order('seq', ascending: true)
            .timeout(requestTimeout);

        final parsed = _parse(turns);

        // A conversation row with no readable turns is not a conversation
        // anybody had. It is what a failed write leaves behind, and listing it
        // offers to open an empty screen.
        if (parsed.isEmpty) continue;

        summaries.add(
          CoachConversationSummary(
            id: id,
            startedAt: started.toLocal(),
            lastTurnAt: last.toLocal(),
            turns: parsed.length,
            // What the lifter said, not what the coach opened with: the coach's
            // first line is the same greeting every time, and would make every
            // row in the list identical.
            opening: parsed
                .where((CoachTurn t) => !t.fromCoach)
                .firstOrNull
                ?.body,
          ),
        );
      }
      return summaries;
    } on Object {
      return const <CoachConversationSummary>[];
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

  /// The conversation each of [asked] was sent in, so a test can assert that a
  /// chip started a new session rather than continuing one.
  final List<String> askedIn = <String>[];

  @override
  Future<String> ask(String message, {required String conversationId}) async {
    asked.add(message);
    askedIn.add(conversationId);
    final failure = failWith;
    if (failure != null) throw CoachException(failure);
    return reply;
  }
}

/// A scripted transcript, for tests and the preview harness.
class FakeCoachTranscript implements CoachTranscript {
  FakeCoachTranscript({
    List<CoachTurn>? turns,
    this.empty = false,
    this.past = const <CoachConversationSummary>[],
    this.openId = 'lift:preview-open',
  }) : _turns = turns ?? _sample();

  final List<CoachTurn> _turns;

  /// Reads as a conversation that never happened. The real one answers this way
  /// on a failed read too, so a screen that handles this handles both.
  ///
  /// Also closes the session: nothing said means nothing open, which is the
  /// state a lifter opening the coach for the first time is in.
  final bool empty;

  /// What the "previous conversations" list finds. Empty by default, because
  /// most previews are of one conversation rather than of a history.
  final List<CoachConversationSummary> past;

  /// The session [openConversationId] reports, when there is one.
  final String openId;

  @override
  Future<List<CoachTurn>> read(String conversationId) async =>
      empty ? const <CoachTurn>[] : _turns;

  @override
  Future<String?> openConversationId({
    Duration window = coachSessionWindow,
  }) async => empty ? null : openId;

  @override
  Future<List<CoachConversationSummary>> conversations({
    int limit = 20,
  }) async => past.take(limit).toList();

  @override
  Future<List<CoachTurn>> fullTranscript(String conversationId) async => _turns;

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
