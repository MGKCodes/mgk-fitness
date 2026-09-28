/// The coach's memory, as domain objects.
///
/// Memory is **tiered**, and the two tiers have opposite lifecycles:
///
/// * [CoachSummary] — a small prose summary, always loaded into the coach's
///   context, **regenerated and replaced** rather than appended to.
/// * [CoachTurn] — the verbatim transcript, append-only, read only on demand.
///
/// Everything here is special-category health data (CLAUDE.md rule 6): a turn
/// holds the runner's own words about their body. Nothing in this file has a
/// `toString` that leaks message text, and nothing may be logged.
library;

/// Who spoke.
///
/// The wire values match the existing intake transcript
/// (`IntakeMessage.role`) and the coach Edge Function's history format, so a
/// stored turn and a live one speak the same vocabulary and no translation
/// layer can drift between them.
enum CoachRole {
  user('user'),
  assistant('assistant');

  const CoachRole(this.wire);

  /// The stored/transmitted value. Constrained by a CHECK in
  /// `runio.coach_turns`.
  final String wire;

  /// The role for [wire], or null if it is not one this build knows.
  ///
  /// Returns null rather than defaulting: a turn whose speaker is unknown must
  /// not be silently attributed to the runner or to the coach.
  static CoachRole? fromWire(String wire) {
    for (final role in CoachRole.values) {
      if (role.wire == wire) return role;
    }
    return null;
  }
}

/// The always-loaded tier: what the coach remembers about this runner, in
/// prose.
///
/// **Replaced, never appended.** Each regeneration produces a whole new
/// summary from the source material; folding a new paragraph onto an old
/// summary would make every version a lossy re-encode of a lossy re-encode,
/// drifting with no way to diff it and no way to tell a fact the runner stated
/// from one the model invented three regenerations ago.
///
/// [model] and [updatedAt] make a bad summary traceable — when a runner says
/// "the coach thinks I'm marathon training and I'm not", the answer to *which
/// model wrote that, and when* has to survive the regeneration that fixes it.
class CoachSummary {
  const CoachSummary({
    required this.text,
    required this.updatedAt,
    this.model,
    this.turnsCovered = 0,
  });

  /// The summary itself. Context for a prompt, never parsed for numbers — a
  /// number the app acts on comes from the validated profile or plan
  /// (CLAUDE.md rule 2).
  final String text;

  /// When this version was generated.
  final DateTime updatedAt;

  /// The `COACH_MODEL` that produced it, if the caller knew it. Null is
  /// honest: the model is server-side configuration, so a build that was not
  /// told which one ran records nothing rather than guessing.
  final String? model;

  /// How many turns were folded in. A staleness signal: turns newer than
  /// [updatedAt] are the ones this summary has not seen.
  final int turnsCovered;
}

/// One turn of a stored conversation — the runner's words or the coach's.
class CoachTurn {
  const CoachTurn({
    required this.conversationId,
    required this.seq,
    required this.role,
    required this.text,
    required this.at,
  });

  final String conversationId;

  /// 0-based position within the conversation.
  ///
  /// Ordering is by [seq], not by [at]: two turns can land on the same clock
  /// tick, and the order the runner and the coach actually spoke in must be
  /// exact.
  final int seq;

  final CoachRole role;

  /// What was said. Special-category data — never logged, never put in an
  /// exception message.
  final String text;

  final DateTime at;

  bool get isUser => role == CoachRole.user;

  /// The id this turn takes in Postgres.
  ///
  /// The local key is the composite `(conversationId, seq)`; Postgres wants a
  /// single column, so it is composed from the same parts — deterministic, so
  /// a re-push updates the same row rather than duplicating a turn. Same
  /// convention as `plan_sessions.id`.
  String get remoteId => '$conversationId-t$seq';

  /// Deliberately says nothing about [text]. A transcript must not reach a log
  /// through a stray interpolation (CLAUDE.md rule 6).
  @override
  String toString() =>
      'CoachTurn($conversationId#$seq, ${role.wire}, ${text.length} chars)';
}

/// How much transcript is kept.
///
/// A transcript of health data that grows forever is not a neutral default: it
/// is a steadily worsening breach if one ever happens, and it is against the
/// data-minimisation principle. Both bounds are needed —
///
/// * [maxAge] alone does not bound a pathologically chatty week;
/// * [maxTurns] alone does not bound how long a quiet runner's words are kept.
///
/// Dropping old verbatim text is safe *because* memory is tiered: the
/// [CoachSummary] is the long-term memory and survives pruning. The transcript
/// is the recent, verbatim record.
class CoachMemoryRetention {
  const CoachMemoryRetention({
    this.maxAge = const Duration(days: 180),
    this.maxTurns = 1000,
  }) : assert(maxTurns == null || maxTurns > 0, 'keep at least one turn');

  /// Turns older than this are pruned. Null disables the age bound.
  ///
  /// Must be positive. Not asserted, because `Duration` comparison is not
  /// const-evaluable and this class is used as a const default — a negative
  /// window would prune the transcript to nothing, which is a mistake no
  /// caller has any reason to make.
  final Duration? maxAge;

  /// At most this many turns are kept per runner, newest first. Null disables
  /// the count bound.
  final int? maxTurns;

  /// Keeps everything, forever.
  ///
  /// Named for what it is so it cannot be reached for casually: unbounded
  /// retention of special-category data is a decision, not a default. Tests
  /// that are about something else use it to hold retention still.
  static const CoachMemoryRetention unboundedForTests = CoachMemoryRetention(
    maxAge: null,
    maxTurns: null,
  );

  /// The instant before which turns are too old to keep, or null when [maxAge]
  /// is disabled.
  DateTime? cutoff(DateTime now) =>
      maxAge == null ? null : now.subtract(maxAge!);

  /// The turns in [newestFirst] this policy does **not** keep.
  ///
  /// Lives here rather than in either store so the device and the in-memory
  /// fake cannot disagree about what "180 days and 1000 turns" means — a
  /// divergence would surface as memory that vanishes on a phone but not in
  /// the preview, which is close to unfindable.
  ///
  /// A prune runs immediately after an append, and **the turn that triggered it
  /// always survives** — not by a special case, but by construction: it is the
  /// newest, so it sits at index 0 and clears a cap of at least one ([maxTurns]
  /// is asserted positive), and it is stamped `now`, so it cannot be before a
  /// cutoff in the past. A special case would have been worse than nothing,
  /// because it would also keep one stale turn of a transcript that has aged
  /// out entirely.
  List<CoachTurn> victims(List<CoachTurn> newestFirst, DateTime now) {
    final by = cutoff(now);
    final cap = maxTurns;
    if (by == null && cap == null) return const <CoachTurn>[];

    return <CoachTurn>[
      for (var i = 0; i < newestFirst.length; i++)
        if ((cap != null && i >= cap) ||
            (by != null && newestFirst[i].at.isBefore(by)))
          newestFirst[i],
    ];
  }
}

/// Newest first, and fully deterministic so a count cap keeps a stable set.
///
/// Within a conversation the tie-break is [CoachTurn.seq] descending, because
/// two turns can share a clock tick and the later one is the later one.
int newestTurnFirst(CoachTurn a, CoachTurn b) {
  final byTime = b.at.compareTo(a.at);
  if (byTime != 0) return byTime;
  final byConversation = a.conversationId.compareTo(b.conversationId);
  return byConversation != 0 ? byConversation : b.seq.compareTo(a.seq);
}

/// How well [text] answers [query]: the number of distinct query terms it
/// contains.
///
/// A crude keyword count, and knowingly so — it is the placeholder behind
/// `CoachMemoryRecall`, which is the seam a semantic search replaces. Terms
/// shorter than three characters are dropped so "my", "a" and "is" do not make
/// every turn equally relevant.
int keywordRelevance(String query, String text) {
  final haystack = text.toLowerCase();
  var score = 0;
  for (final term in relevanceTerms(query)) {
    if (haystack.contains(term)) score++;
  }
  return score;
}

/// The distinct, lowercased, meaningful terms of [query].
Set<String> relevanceTerms(String query) => <String>{
  for (final term in query.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
    if (term.length >= 3) term,
};

/// A past conversation, as the "previous chats" list needs it.
///
/// Built from `CoachConversations` wherever it can be: that table carries a
/// denormalised [lastTurnAt] precisely so listing recent conversations is an
/// indexed lookup rather than an aggregate over the largest table in the
/// schema.
///
/// [opening] is the first thing said in it, which is what turns a list of dates
/// into a list a person recognises. Special-category data like any other turn
/// (CLAUDE.md rule 6) — it is drawn on the runner's own screen and never
/// logged, and [toString] deliberately omits it.
class CoachConversationSummary {
  const CoachConversationSummary({
    required this.id,
    required this.kind,
    required this.startedAt,
    required this.lastTurnAt,
    this.turns = 0,
    this.opening,
  });

  final String id;

  /// `intake` | `check_in` | `adaptation` | `coach`.
  final String kind;

  final DateTime startedAt;

  /// When it was last spoken in — what the list is ordered by.
  final DateTime lastTurnAt;

  /// How many turns it holds.
  final int turns;

  /// The first line of the conversation, or null when it has none.
  final String? opening;

  @override
  String toString() =>
      'CoachConversationSummary($id, $kind, $turns turns, last $lastTurnAt)';
}

/// How long a conversation stays open with nothing said in it.
///
/// **This is the session boundary**, and it is a gap rather than a lifecycle
/// event on purpose — see ADR-0025. Measured from the last turn, one rule
/// settles both the cold start and the trip to the home screen: a runner who
/// checks a notification and comes back in ten seconds is still in the same
/// conversation; one who comes back tomorrow is not.
const Duration coachSessionWindow = Duration(minutes: 30);

/// The past turns worth putting in front of the coach, out of what
/// `CoachMemoryRepository.recall` returned.
///
/// Three filters, and each one is a failure this app has already seen or is one
/// step away from:
///
/// * **The current conversation is dropped.** Its turns are already the chat
///   history the coach is sent; recalling them would double-weight what was
///   just said.
/// * **Only the runner's own words survive.** The coach's past replies were
///   themselves derived from a brief that is rebuilt from current data every
///   turn, so re-injecting one launders a stale derivation back into the
///   context as if it were a fact. What the runner said is primary evidence;
///   what the coach said is a conclusion with an expiry date.
/// * **It is small.** Recall is context, not a transcript. The whole reason it
///   exists is that replaying a transcript is what placed a week-old run
///   "yesterday".
List<CoachTurn> recollectionsFrom(
  List<CoachTurn> turns, {
  String? exceptConversation,
  int limit = 4,
}) => <CoachTurn>[
  for (final turn in turns)
    if (turn.isUser && turn.conversationId != exceptConversation) turn,
].take(limit < 0 ? 0 : limit).toList();
