/// Local mirror of the coach's memory — the **source of truth** for it, with
/// `runio.coach_summaries` / `coach_conversations` / `coach_turns` as the
/// backup (CLAUDE.md rule 1, and see the migration
/// `20260727090000_coach_memory.sql` for the reasoning behind the shape).
///
/// Like `Plans`, these rows carry no `user_id`: the local database belongs to
/// the one signed-in runner. The Postgres rows do carry it — RLS checks it, and
/// it is what enrols a table in the account-deletion sweep.
library;

import 'package:drift/drift.dart';

/// The always-loaded tier: what the coach remembers, in prose.
///
/// **Replaced, never appended**, and the schema is what makes that true rather
/// than a convention — the primary key is a fixed constant
/// ([coachSummarySingletonId]), so an upsert can only ever overwrite the single
/// row. There is no shape of this table that accumulates summaries.
@DataClassName('CoachSummaryRow')
class CoachSummaries extends Table {
  /// Always [coachSummarySingletonId]. Present only because Drift wants a key;
  /// it is the Postgres `user_id` primary key's local equivalent.
  TextColumn get id =>
      text().withDefault(const Constant(coachSummarySingletonId))();

  /// Context for a prompt, never parsed for numbers.
  TextColumn get summary => text()();

  /// The `COACH_MODEL` that produced it, so a bad summary is traceable to the
  /// model and moment that wrote it. Null when the build was not told.
  TextColumn get model => text().nullable()();

  /// How many turns were folded in — a staleness signal alongside [updatedAt].
  IntColumn get turnsCovered => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A coach conversation — the unit a transcript belongs to.
@DataClassName('CoachConversationRow')
class CoachConversations extends Table {
  /// Client-generated id, shared with the Supabase row. Same convention as
  /// `Runs.id` and `Plans.id`.
  TextColumn get id => text()();

  /// Free-form label: `intake` | `check_in` | `adaptation` | `coach`.
  TextColumn get kind => text().withDefault(const Constant('coach'))();

  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();

  /// Denormalised from the turns so "recent conversations" is an indexed
  /// lookup rather than an aggregate over the largest table here.
  DateTimeColumn get lastTurnAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One turn of a stored conversation — **append-only**, and pruned to a
/// rolling window (`CoachMemoryRetention`) because a transcript of health data
/// that grows forever is not a neutral default.
///
/// The column is `body`, not `text`, because a Drift table already has a
/// `text()` column builder and a getter of that name would shadow it.
@DataClassName('CoachTurnRow')
class CoachTurns extends Table {
  TextColumn get conversationId => text().references(CoachConversations, #id)();

  /// 0-based position within the conversation. Ordering is by this, not by
  /// [createdAt]: two turns can share a clock tick and the order the runner and
  /// the coach spoke in must be exact.
  IntColumn get seq => integer()();

  /// `user` | `assistant`, matching `IntakeMessage.role` and the coach
  /// function's history format.
  TextColumn get role => text()();

  /// What was said. Special-category data (CLAUDE.md rule 6) — never logged.
  TextColumn get body => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {conversationId, seq};
}

/// The one and only key of the local summary row. See [CoachSummaries].
const String coachSummarySingletonId = 'current';
