import '../domain/coach_memory.dart';

/// The default label for a conversation whose kind the caller did not state.
const String coachConversationKindDefault = 'coach';

/// Local persistence for the coach's memory — **the source of truth**
/// (CLAUDE.md rule 1). Every method here works with no network; Supabase is a
/// mirror reached separately via [CoachMemoryMirror].
///
/// Implementations: [DriftCoachMemoryStore] on device,
/// [InMemoryCoachMemoryStore] for tests and the preview harness.
abstract interface class CoachMemoryStore {
  /// The runner's current summary, or null if the coach has not written one
  /// yet.
  ///
  /// Local only, so it resolves in a tunnel. Throws [CoachMemoryException] if a
  /// summary exists but cannot be read — "no memory yet" and "your memory is
  /// unreadable" must not look the same.
  Future<CoachSummary?> loadSummary();

  /// **Replaces** the summary. There is one per runner and this overwrites it;
  /// there is deliberately no "append to summary".
  Future<void> saveSummary(CoachSummary summary);

  /// Appends a turn, creating the conversation if this is its first.
  ///
  /// [seq] is assigned by the store as the next position in the conversation,
  /// so two callers cannot disagree about ordering. [kind] labels the
  /// conversation and is used **only** when creating it — it never relabels an
  /// existing one.
  ///
  /// The returned future completes only once the turn is on disk.
  Future<CoachTurn> appendTurn({
    required String conversationId,
    required CoachRole role,
    required String text,
    String kind = coachConversationKindDefault,
    DateTime? at,
  });

  /// A conversation's turns in the order they were spoken. Empty for a
  /// conversation that does not exist — an absent transcript is not an error.
  Future<List<CoachTurn>> loadTurns(String conversationId);

  /// The most recent turns across every conversation, newest first.
  ///
  /// Bounded by [limit] on purpose: this is the scan [KeywordRecall] searches,
  /// and an unbounded read of the whole transcript into memory is not
  /// something a caller should be able to ask for by accident.
  Future<List<CoachTurn>> recentTurns({int limit = 300});

  /// The conversations spoken in most recently, newest first — what the
  /// "previous chats" list draws.
  ///
  /// Ordered by `lastTurnAt`, which is denormalised onto the conversation row
  /// for exactly this: the list is one bounded read of the small table, not an
  /// aggregate over the transcript.
  Future<List<CoachConversationSummary>> recentConversations({int limit = 20});

  /// Applies [policy], deleting the turns that fall outside it and any
  /// conversation left with none. Returns what was removed, newest first.
  ///
  /// Idempotent: running it twice removes nothing the second time.
  Future<List<CoachTurn>> prune(CoachMemoryRetention policy, {DateTime? now});
}

/// Finding turns relevant to a question.
///
/// **This is the seam.** Today the only implementation is [KeywordRecall],
/// which counts matching words. Semantic search — embeddings, a vector index,
/// a reranker — replaces this object and nothing else: [CoachMemoryRepository]
/// takes it as a constructor argument and callers only ever see
/// `repository.recall(query)`. Neither [CoachMemoryStore] nor any caller
/// changes.
abstract interface class CoachMemoryRecall {
  /// The [limit] turns most relevant to [query], most relevant first.
  /// Returns empty rather than falling back to "most recent" — "nothing you
  /// said matches" is a real and useful answer.
  Future<List<CoachTurn>> search(String query, {int limit});
}

/// The mirror / cross-device half: a best-effort copy of what is already
/// safely on disk. Never on a read path, and never allowed to fail a write —
/// the coach's memory does not depend on the network.
abstract interface class CoachMemoryMirror {
  Future<void> pushSummary(CoachSummary summary);

  /// Mirrors one appended turn, and the conversation it belongs to.
  Future<void> pushTurn(CoachTurn turn, {required String kind});

  /// Re-applies the retention window remotely, as a single delete of
  /// everything older than [olderThan].
  ///
  /// Expressed as a cutoff rather than a list of ids so it is **self-healing**:
  /// a prune that happened while the device was offline is simply re-applied by
  /// the next one, instead of leaving orphaned rows on the server forever.
  Future<void> pushPrune({required DateTime olderThan});
}

/// The coach's memory could not be read or written. Raised rather than
/// swallowed — but note that the message never contains transcript text
/// (CLAUDE.md rule 6); an exception is one of the easiest ways for
/// special-category data to reach a log.
class CoachMemoryException implements Exception {
  const CoachMemoryException(this.message);

  final String message;

  @override
  String toString() => 'CoachMemoryException: $message';
}

/// The default [CoachMemoryRecall]: a keyword count over the recent transcript.
///
/// Honest about what it is. It will match "calf" in "my calf is sore" and miss
/// it in "lower leg pain" — that gap is the reason [CoachMemoryRecall] is an
/// interface rather than a method body.
class KeywordRecall implements CoachMemoryRecall {
  const KeywordRecall(this._store, {this.scanLimit = 300});

  final CoachMemoryStore _store;

  /// How far back the scan reaches. Bounded so recall cost does not grow with
  /// the transcript.
  final int scanLimit;

  @override
  Future<List<CoachTurn>> search(String query, {int limit = 8}) async {
    if (relevanceTerms(query).isEmpty || limit <= 0) return const <CoachTurn>[];

    final turns = await _store.recentTurns(limit: scanLimit);
    final scored = <({CoachTurn turn, int score})>[
      for (final turn in turns)
        if (keywordRelevance(query, turn.text) > 0)
          (turn: turn, score: keywordRelevance(query, turn.text)),
    ];
    // Most relevant first; among equally relevant turns, the most recent —
    // "since the half" means the latest mention, not the first.
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : b.turn.at.compareTo(a.turn.at);
    });
    return <CoachTurn>[for (final s in scored.take(limit)) s.turn];
  }
}

/// An in-memory [CoachMemoryStore]. The default when nothing is injected, so
/// the coach has exactly one code path whether or not a database is wired up,
/// and the preview harness exercises the real read/write flow with no Supabase
/// and no device plugins.
///
/// Not durable across launches — that is [DriftCoachMemoryStore]'s job.
class InMemoryCoachMemoryStore implements CoachMemoryStore {
  /// One field, not a list. The "replaced, never appended" invariant is the
  /// same here as the single-row primary key is in Postgres.
  CoachSummary? _summary;

  final Map<String, String> _kinds = <String, String>{};
  final List<CoachTurn> _turns = <CoachTurn>[];

  @override
  Future<CoachSummary?> loadSummary() async => _summary;

  @override
  Future<void> saveSummary(CoachSummary summary) async => _summary = summary;

  @override
  Future<CoachTurn> appendTurn({
    required String conversationId,
    required CoachRole role,
    required String text,
    String kind = coachConversationKindDefault,
    DateTime? at,
  }) async {
    _kinds.putIfAbsent(conversationId, () => kind);
    final turn = CoachTurn(
      conversationId: conversationId,
      seq: _nextSeq(conversationId),
      role: role,
      text: text,
      at: at ?? DateTime.now(),
    );
    _turns.add(turn);
    return turn;
  }

  @override
  Future<List<CoachTurn>> loadTurns(String conversationId) async => <CoachTurn>[
    for (final t in _turns)
      if (t.conversationId == conversationId) t,
  ]..sort((a, b) => a.seq.compareTo(b.seq));

  @override
  Future<List<CoachTurn>> recentTurns({int limit = 300}) async {
    final all = <CoachTurn>[..._turns]..sort(newestTurnFirst);
    return all.take(limit).toList();
  }

  @override
  Future<List<CoachConversationSummary>> recentConversations({
    int limit = 20,
  }) async {
    // Folded from the turns because that is all this store holds; the Drift
    // store reads the denormalised `lastTurnAt` off the conversation row
    // instead. Both answer the same question in the same order, which is the
    // property that matters — a preview and a phone disagreeing about which
    // conversation is "the last one" would be close to unfindable.
    final byId = <String, List<CoachTurn>>{};
    for (final turn in _turns) {
      (byId[turn.conversationId] ??= <CoachTurn>[]).add(turn);
    }

    final summaries = <CoachConversationSummary>[
      for (final entry in byId.entries)
        () {
          final turns = <CoachTurn>[...entry.value]
            ..sort((a, b) => a.seq.compareTo(b.seq));
          return CoachConversationSummary(
            id: entry.key,
            kind: _kinds[entry.key] ?? coachConversationKindDefault,
            startedAt: turns.first.at,
            lastTurnAt: turns.last.at,
            turns: turns.length,
            opening: turns.first.text,
          );
        }(),
    ]..sort((a, b) => b.lastTurnAt.compareTo(a.lastTurnAt));

    return summaries.take(limit < 0 ? 0 : limit).toList();
  }

  @override
  Future<List<CoachTurn>> prune(
    CoachMemoryRetention policy, {
    DateTime? now,
  }) async {
    final ordered = <CoachTurn>[..._turns]..sort(newestTurnFirst);
    final removed = policy.victims(ordered, now ?? DateTime.now());
    if (removed.isEmpty) return const <CoachTurn>[];

    final gone = <String>{for (final t in removed) _key(t)};
    _turns.removeWhere((t) => gone.contains(_key(t)));
    // A conversation with no turns left is not a conversation.
    _kinds.removeWhere((id, _) => !_turns.any((t) => t.conversationId == id));
    return removed;
  }

  /// The kind recorded for [conversationId], for the mirror. Null if unknown.
  String? kindOf(String conversationId) => _kinds[conversationId];

  int _nextSeq(String conversationId) {
    var next = 0;
    for (final t in _turns) {
      if (t.conversationId == conversationId && t.seq >= next) next = t.seq + 1;
    }
    return next;
  }

  static String _key(CoachTurn t) => '${t.conversationId}#${t.seq}';
}
