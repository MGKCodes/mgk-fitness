import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/coach_memory_tables.dart';
import '../domain/coach_memory.dart';
import 'coach_memory_store.dart';

/// The production [CoachMemoryStore]: the coach's memory lives in the on-device
/// database, which is the source of truth (CLAUDE.md rule 1). Every read here
/// is local, so the coach still knows who it is talking to in airplane mode.
///
/// Queries are written here rather than on [AppDatabase] deliberately — the
/// shared database class only registers the tables, so this feature's storage
/// stays in the feature.
///
/// Decoding is **strict**, matching `DriftPlanStore`: a row that cannot be
/// mapped back (an unknown role) raises [CoachMemoryException] rather than
/// being skipped. Silently dropping a turn would make the coach mis-remember a
/// conversation, which is worse than failing loudly.
class DriftCoachMemoryStore implements CoachMemoryStore {
  DriftCoachMemoryStore(this._db);

  final AppDatabase _db;

  // --- the rolling summary ----------------------------------------------------

  @override
  Future<CoachSummary?> loadSummary() async {
    final row =
        await (_db.select(_db.coachSummaries)
              ..where((s) => s.id.equals(coachSummarySingletonId))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return CoachSummary(
      text: row.summary,
      updatedAt: row.updatedAt,
      model: row.model,
      turnsCovered: row.turnsCovered,
    );
  }

  @override
  Future<void> saveSummary(CoachSummary summary) async {
    // An upsert on a constant key: the previous summary is overwritten, and no
    // sequence of calls can leave two rows behind. Replacement is structural,
    // not a rule this method is trusted to follow.
    await _db
        .into(_db.coachSummaries)
        .insertOnConflictUpdate(
          CoachSummariesCompanion.insert(
            id: const Value(coachSummarySingletonId),
            summary: summary.text,
            model: Value(summary.model),
            turnsCovered: Value(summary.turnsCovered),
            updatedAt: Value(summary.updatedAt),
          ),
        );
  }

  // --- the transcript ---------------------------------------------------------

  @override
  Future<CoachTurn> appendTurn({
    required String conversationId,
    required CoachRole role,
    required String text,
    String kind = coachConversationKindDefault,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    // One transaction: a turn whose conversation row did not commit would be
    // unreachable, and a `seq` read outside the write could be raced.
    return _db.transaction(() async {
      final existing =
          await (_db.select(_db.coachConversations)
                ..where((c) => c.id.equals(conversationId))
                ..limit(1))
              .getSingleOrNull();

      if (existing == null) {
        await _db
            .into(_db.coachConversations)
            .insert(
              CoachConversationsCompanion.insert(
                id: conversationId,
                kind: Value(kind),
                startedAt: Value(now),
                lastTurnAt: Value(now),
              ),
            );
      } else {
        // `kind` is not rewritten: it labels the conversation as it was
        // started, and a later caller passing the default must not relabel it.
        await (_db.update(_db.coachConversations)
              ..where((c) => c.id.equals(conversationId)))
            .write(CoachConversationsCompanion(lastTurnAt: Value(now)));
      }

      final seq = await _nextSeq(conversationId);
      await _db
          .into(_db.coachTurns)
          .insert(
            CoachTurnsCompanion.insert(
              conversationId: conversationId,
              seq: seq,
              role: role.wire,
              body: text,
              createdAt: Value(now),
            ),
          );

      return CoachTurn(
        conversationId: conversationId,
        seq: seq,
        role: role,
        text: text,
        at: now,
      );
    });
  }

  @override
  Future<List<CoachTurn>> loadTurns(String conversationId) async {
    final rows =
        await (_db.select(_db.coachTurns)
              ..where((t) => t.conversationId.equals(conversationId))
              ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
            .get();
    return <CoachTurn>[for (final row in rows) _turnFrom(row)];
  }

  @override
  Future<List<CoachTurn>> recentTurns({int limit = 300}) async {
    final rows =
        await (_db.select(_db.coachTurns)
              ..orderBy([
                (t) => OrderingTerm.desc(t.createdAt),
                (t) => OrderingTerm.asc(t.conversationId),
                (t) => OrderingTerm.desc(t.seq),
              ])
              ..limit(limit))
            .get();
    return <CoachTurn>[for (final row in rows) _turnFrom(row)];
  }

  @override
  Future<List<CoachConversationSummary>> recentConversations({
    int limit = 20,
  }) async {
    // The read `lastTurnAt` was denormalised for: `limit` rows off the small
    // table, ordered by an indexed column, with no aggregate over the
    // transcript.
    final conversations =
        await (_db.select(_db.coachConversations)
              ..orderBy([(c) => OrderingTerm.desc(c.lastTurnAt)])
              ..limit(limit < 0 ? 0 : limit))
            .get();
    if (conversations.isEmpty) return const <CoachConversationSummary>[];

    // The opening line and the turn count in one further query rather than one
    // per conversation. A list of twenty dates is not a list anybody can
    // recognise themselves in, and the first thing said is what makes it one.
    //
    // It reads the turns rather than aggregating in SQL, and that is a choice:
    // the earliest *surviving* turn is what should open a conversation, and a
    // `seq = 0` filter would leave a pruned conversation with no opening at
    // all. The read is bounded by retention — `maxTurns` caps the whole
    // transcript at 1000 narrow rows — and only happens when the list is
    // opened.
    final ids = <String>[for (final c in conversations) c.id];
    final turns = await (_db.select(
      _db.coachTurns,
    )..where((t) => t.conversationId.isIn(ids))).get();

    final counts = <String, int>{};
    final openings = <String, CoachTurnRow>{};
    for (final turn in turns) {
      counts[turn.conversationId] = (counts[turn.conversationId] ?? 0) + 1;
      final current = openings[turn.conversationId];
      if (current == null || turn.seq < current.seq) {
        openings[turn.conversationId] = turn;
      }
    }

    return <CoachConversationSummary>[
      for (final row in conversations)
        CoachConversationSummary(
          id: row.id,
          kind: row.kind,
          startedAt: row.startedAt,
          lastTurnAt: row.lastTurnAt,
          turns: counts[row.id] ?? 0,
          opening: openings[row.id]?.body,
        ),
    ];
  }

  // --- retention --------------------------------------------------------------

  @override
  Future<List<CoachTurn>> prune(CoachMemoryRetention policy, {DateTime? now}) {
    return _db.transaction(() async {
      // Reading the transcript to decide is affordable precisely because this
      // runs on every append: the table is already held at the policy's cap, so
      // this is a scan of ~`maxTurns` narrow rows, not of unbounded history.
      final rows =
          await (_db.select(_db.coachTurns)..orderBy([
                (t) => OrderingTerm.desc(t.createdAt),
                (t) => OrderingTerm.asc(t.conversationId),
                (t) => OrderingTerm.desc(t.seq),
              ]))
              .get();

      final ordered = <CoachTurn>[for (final row in rows) _turnFrom(row)];
      // The policy itself decides — shared with InMemoryCoachMemoryStore so the
      // device and the preview cannot drift apart on what is kept.
      final removed = policy.victims(ordered, now ?? DateTime.now());
      if (removed.isEmpty) return const <CoachTurn>[];

      // Grouped by conversation so this is one statement per affected
      // conversation — after a routine append-and-prune that is zero or one.
      final byConversation = <String, List<int>>{};
      for (final turn in removed) {
        (byConversation[turn.conversationId] ??= <int>[]).add(turn.seq);
      }

      for (final entry in byConversation.entries) {
        await (_db.delete(_db.coachTurns)..where(
              (t) =>
                  t.conversationId.equals(entry.key) & t.seq.isIn(entry.value),
            ))
            .go();

        // A conversation with no turns left is not a conversation. Dropping it
        // keeps the table from filling with tombstones of erased transcripts.
        final remaining =
            await (_db.select(_db.coachTurns)
                  ..where((t) => t.conversationId.equals(entry.key))
                  ..limit(1))
                .getSingleOrNull();
        if (remaining == null) {
          await (_db.delete(
            _db.coachConversations,
          )..where((c) => c.id.equals(entry.key))).go();
        }
      }

      return removed;
    });
  }

  // --- row → domain -----------------------------------------------------------

  Future<int> _nextSeq(String conversationId) async {
    final last =
        await (_db.select(_db.coachTurns)
              ..where((t) => t.conversationId.equals(conversationId))
              ..orderBy([(t) => OrderingTerm.desc(t.seq)])
              ..limit(1))
            .getSingleOrNull();
    return last == null ? 0 : last.seq + 1;
  }

  CoachTurn _turnFrom(CoachTurnRow row) {
    final role = CoachRole.fromWire(row.role);
    if (role == null) {
      // The turn's text is deliberately not in the message: an exception is one
      // of the easiest ways for special-category data to reach a log.
      throw CoachMemoryException(
        'turn ${row.conversationId}#${row.seq} has unknown role "${row.role}"',
      );
    }
    return CoachTurn(
      conversationId: row.conversationId,
      seq: row.seq,
      role: role,
      text: row.body,
      at: row.createdAt,
    );
  }
}
