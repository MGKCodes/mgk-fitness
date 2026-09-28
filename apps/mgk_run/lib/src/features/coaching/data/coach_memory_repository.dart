import '../domain/coach_memory.dart';
import 'coach_memory_store.dart';

/// The coach's memory, as the rest of the app sees it.
///
/// Memory is **tiered**: a small rolling [summary] that is always loaded, and
/// the verbatim transcript that is stored but only read when something is
/// looked up ([transcript], [recall]).
///
/// **Offline-first (CLAUDE.md rule 1):** every read and every write goes to the
/// local [CoachMemoryStore] first and completes there. [CoachMemoryMirror] is
/// then poked best-effort; a failed or absent mirror can never fail a write or
/// block a read, so the coach still remembers the runner in a tunnel.
///
/// **Special-category data (rule 6):** a transcript holds the runner's own
/// words about their body. Nothing here logs, and the mirror's failures are
/// swallowed silently rather than reported with context that would carry
/// message text.
class CoachMemoryRepository {
  CoachMemoryRepository({
    required CoachMemoryStore store,
    CoachMemoryMirror? mirror,
    CoachMemoryRecall? recall,
    this.retention = const CoachMemoryRetention(),
    DateTime Function() now = DateTime.now,
  }) : _store = store,
       _mirror = mirror,
       _recall = recall ?? KeywordRecall(store),
       _now = now;

  final CoachMemoryStore _store;
  final CoachMemoryMirror? _mirror;
  final CoachMemoryRecall _recall;
  final DateTime Function() _now;

  /// How much transcript is kept. Applied on every append — see
  /// [CoachMemoryRetention] for why both bounds exist.
  final CoachMemoryRetention retention;

  // --- the always-loaded tier -------------------------------------------------

  /// What the coach remembers about this runner, or null if it has not written
  /// a summary yet.
  ///
  /// Local only — no network — because this is loaded into the context of every
  /// coach turn and must not be able to hang one.
  Future<CoachSummary?> summary() => _store.loadSummary();

  /// **Replaces** the summary with a freshly generated one.
  ///
  /// Named `replace`, not `update`, because that is the whole design: a summary
  /// is regenerated from source and overwritten. There is deliberately no way
  /// to append to it — appending would make each version a lossy re-encode of a
  /// lossy re-encode, drifting with nothing to diff against.
  ///
  /// [model] should be the `COACH_MODEL` that produced [text], so a summary
  /// that turns out to be wrong can be traced to the model and moment that
  /// wrote it.
  Future<CoachSummary> replaceSummary(
    String text, {
    String? model,
    int turnsCovered = 0,
  }) async {
    final summary = CoachSummary(
      text: text,
      updatedAt: _now(),
      model: model,
      turnsCovered: turnsCovered,
    );
    await _store.saveSummary(summary);
    await _bestEffort(() => _mirror?.pushSummary(summary));
    return summary;
  }

  // --- the transcript ---------------------------------------------------------

  /// Appends a turn to [conversationId]'s transcript, creating the conversation
  /// if this is its first turn.
  ///
  /// The returned future completes only once the turn is **on disk**, so a
  /// force-quit straight after sending keeps it. [kind] labels the conversation
  /// (`intake` | `check_in` | `adaptation` | `coach`) and applies only when it
  /// is created — it never relabels an existing conversation.
  ///
  /// Retention is applied here, in the same call, rather than by a sweep
  /// somewhere else: pruning that only runs if something remembers to schedule
  /// it is how a table of health data quietly becomes unbounded.
  Future<CoachTurn> appendTurn({
    required String conversationId,
    required CoachRole role,
    required String text,
    String kind = coachConversationKindDefault,
  }) async {
    final turn = await _store.appendTurn(
      conversationId: conversationId,
      role: role,
      text: text,
      kind: kind,
      at: _now(),
    );
    await _store.prune(retention, now: _now());
    await _bestEffort(() => _mirror?.pushTurn(turn, kind: kind));
    await _pushPrune();
    return turn;
  }

  /// The conversation still open at [window], or null when the last thing said
  /// is older than that.
  ///
  /// **This is the session boundary** (ADR-0025). It replaces an unconditional
  /// `lastConversationId()`, which is what the dock used to restore on launch —
  /// so a conversation from last Tuesday was picked back up on Thursday and the
  /// coach read week-old context as current. It once answered *"You ran 10 km
  /// in 60 minutes yesterday"* about a run logged a week earlier, which was a
  /// true memory placed in the wrong week rather than an invention. The
  /// unconditional version is deliberately gone rather than kept alongside
  /// this one: two ways to answer "which conversation?" is how the wrong one
  /// gets reached for again.
  ///
  /// A gap, not a lifecycle event. One rule covers a cold start and a trip to
  /// the home screen, and a runner who checks a notification and comes back in
  /// ten seconds keeps their conversation. Derived from the turns rather than
  /// stored as a pointer — a pointer is one more thing that can disagree with
  /// the table it points into, and the answer is one row deep. Local only:
  /// restoring the dock must not wait on a network.
  Future<String?> openConversationId({
    Duration window = coachSessionWindow,
  }) async {
    final recent = await _store.recentTurns(limit: 1);
    if (recent.isEmpty) return null;
    final last = recent.first;
    return _now().difference(last.at) > window ? null : last.conversationId;
  }

  /// The conversations spoken in most recently, newest first — the "previous
  /// chats" list.
  ///
  /// Sessions mean the dock no longer opens on last week's transcript, so this
  /// is where last week's transcript went. Local only, and bounded: the coach's
  /// memory is pruned to a rolling window ([CoachMemoryRetention]), so this
  /// lists what is kept rather than everything ever said.
  Future<List<CoachConversationSummary>> conversations({int limit = 20}) =>
      _store.recentConversations(limit: limit);

  /// A conversation's turns, in the order they were spoken. Local only.
  Future<List<CoachTurn>> transcript(String conversationId) =>
      _store.loadTurns(conversationId);

  /// The turns most relevant to [query], most relevant first — the "read it
  /// only when asked" half of tiered memory.
  ///
  /// Delegates to the injected [CoachMemoryRecall]. Today that is
  /// [KeywordRecall] and the matching is a word count; swapping in semantic
  /// search means passing a different `recall` to this constructor and changes
  /// nothing here and nothing in any caller.
  Future<List<CoachTurn>> recall(String query, {int limit = 8}) =>
      _recall.search(query, limit: limit);

  // --- mirror: best effort, never load-bearing --------------------------------

  /// Re-applies the retention window on the server.
  ///
  /// Unconditional, not "only when the local prune removed something" — that is
  /// what makes it self-healing. A prune that happened while the device was
  /// offline removes nothing locally next time, so a conditional push would
  /// leave the server holding transcript rows the device erased months ago.
  Future<void> _pushPrune() async {
    final olderThan = retention.cutoff(_now());
    if (olderThan == null) return;
    await _bestEffort(() => _mirror?.pushPrune(olderThan: olderThan));
  }

  /// Runs a mirror push, swallowing anything it throws. The local write has
  /// already committed, so a dead network is not an error the runner needs to
  /// see. Deliberately silent — the coach's memory is health data and
  /// CLAUDE.md rule 6 forbids logging it.
  Future<void> _bestEffort(Future<void>? Function() push) async {
    try {
      await push();
    } catch (_) {
      // Ignored on purpose — see above.
    }
  }
}
