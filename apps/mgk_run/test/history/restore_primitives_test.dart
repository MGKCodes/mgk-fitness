import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';

/// The one guarantee the restore rests on: **a row the phone already has always
/// wins.** Everything else about the pull is plumbing; this is the part that
/// decides whether a restore can lose data.
///
/// Tested against a real in-memory database rather than a mock, because the
/// behaviour under test is SQLite's conflict handling, not Dart's.
void main() {
  late AppDatabase db;

  final ranAt = DateTime(2026, 7, 20, 7, 30);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  RunsCompanion run(String id, double distance) => RunsCompanion.insert(
    id: id,
    startedAt: ranAt,
    durationS: 1800,
    distanceM: distance,
    source: 'gps',
    type: 'outdoor',
  );

  // ---- runs ----------------------------------------------------------------

  test('a restored run does not overwrite the local one', () async {
    // The scenario: the runner corrected this run on the phone while offline,
    // and the server still holds the original. The pull must not undo the edit.
    await db.upsertRun(run('r1', 5500));
    await db.restoreRuns(<RunsCompanion>[run('r1', 5000)]);

    final row = await db.runById('r1');
    expect(row!.distanceM, 5500, reason: 'the local correction must survive');
  });

  test('a restored run the phone has never seen is inserted', () async {
    await db.restoreRuns(<RunsCompanion>[run('r1', 5000)]);
    expect((await db.runById('r1'))!.distanceM, 5000);
  });

  test('one batch mixes new rows and rows already held', () async {
    await db.upsertRun(run('r1', 5500));
    await db.restoreRuns(<RunsCompanion>[run('r1', 5000), run('r2', 8000)]);

    expect((await db.runById('r1'))!.distanceM, 5500);
    expect((await db.runById('r2'))!.distanceM, 8000);
    expect(await db.allRuns(), hasLength(2));
  });

  test('restoring the same runs twice changes nothing', () async {
    // A restore is repeatable by design: it runs at launch over a connection
    // nobody promised, so a partial pull has to be safe to continue.
    await db.restoreRuns(<RunsCompanion>[run('r1', 5000)]);
    await db.restoreRuns(<RunsCompanion>[run('r1', 5000)]);
    expect(await db.allRuns(), hasLength(1));
  });

  // ---- what it reports ------------------------------------------------------
  //
  // The count is the whole content of the sentence a runner is shown after a
  // restore, and it was the *fetched* row count until 2026-09-08 — so a phone
  // that already had everything still reported restoring all of it, on every
  // launch, forever. Build 13 saw that as the message arriving again and again.
  // Asserted at this level because it is a claim about the database, not about
  // a screen.

  test(
    'a restore reports the rows it inserted, not the rows offered',
    () async {
      expect(
        await db.restoreRuns(<RunsCompanion>[run('r1', 5000), run('r2', 8000)]),
        2,
      );
    },
  );

  test('a second identical restore reports nothing', () async {
    await db.restoreRuns(<RunsCompanion>[run('r1', 5000)]);
    expect(
      await db.restoreRuns(<RunsCompanion>[run('r1', 5000)]),
      0,
      reason: 'nothing arrived, so there is nothing to announce',
    );
  });

  test('a mixed batch counts only what was new', () async {
    await db.upsertRun(run('r1', 5500));
    expect(
      await db.restoreRuns(<RunsCompanion>[run('r1', 5000), run('r2', 8000)]),
      1,
      reason: 'r1 was already held and lost the conflict',
    );
  });

  // ---- the trace -----------------------------------------------------------

  test('restored points do not duplicate a trace already held', () async {
    await db.upsertRun(run('r1', 5000));
    RunPointsCompanion pt(int seq) => RunPointsCompanion.insert(
      runId: 'r1',
      seq: seq,
      lat: 51.5,
      lng: -0.12,
      accuracyM: 5,
      timestamp: ranAt,
    );

    await db.addRunPoint(pt(0));
    await db.restoreRunPoints(<RunPointsCompanion>[pt(0), pt(1)]);

    // (run_id, seq) is the key, so point 0 is ignored and point 1 lands.
    expect(await db.pointsForRun('r1'), hasLength(2));
  });

  // ---- the coach's memory --------------------------------------------------

  test('a restored transcript cannot rewrite a turn already held', () async {
    // The strongest form of the rule. A transcript is append-only — UPDATE is
    // revoked on the server table — so a restore that overwrote a turn would
    // be rewriting a record of what the runner said about their own body.
    await db.restoreCoachMemory(
      conversations: <CoachConversationsCompanion>[
        CoachConversationsCompanion.insert(id: 'c1'),
      ],
      turns: <CoachTurnsCompanion>[
        CoachTurnsCompanion.insert(
          conversationId: 'c1',
          seq: 0,
          role: 'user',
          body: 'what the runner actually said',
        ),
      ],
    );

    await db.restoreCoachMemory(
      conversations: <CoachConversationsCompanion>[
        CoachConversationsCompanion.insert(id: 'c1'),
      ],
      turns: <CoachTurnsCompanion>[
        CoachTurnsCompanion.insert(
          conversationId: 'c1',
          seq: 0,
          role: 'user',
          body: 'something else entirely',
        ),
      ],
    );

    final turns = await db.select(db.coachTurns).get();
    expect(turns, hasLength(1));
    expect(turns.single.body, 'what the runner actually said');
  });

  test('the local summary is never replaced by an older one', () async {
    // One row, replaced never appended. The phone's copy is the newer of the
    // two whenever it has been used since the last push.
    await db.restoreCoachSummary(
      CoachSummariesCompanion.insert(summary: 'what the coach knows now'),
    );
    await db.restoreCoachSummary(
      CoachSummariesCompanion.insert(summary: 'a stale copy from the server'),
    );

    final rows = await db.select(db.coachSummaries).get();
    expect(rows, hasLength(1));
    expect(rows.single.summary, 'what the coach knows now');
  });

  // ---- the guards the restore asks first -----------------------------------

  test('hasNoPlan and hasNoCoachMemory answer for an empty phone', () async {
    expect(await db.hasNoPlan(), isTrue);
    expect(await db.hasNoCoachMemory(), isTrue);

    await db.restoreCoachMemory(
      conversations: <CoachConversationsCompanion>[
        CoachConversationsCompanion.insert(id: 'c1'),
      ],
      turns: <CoachTurnsCompanion>[
        CoachTurnsCompanion.insert(
          conversationId: 'c1',
          seq: 0,
          role: 'user',
          body: 'hello',
        ),
      ],
    );
    expect(await db.hasNoCoachMemory(), isFalse);
  });

  test('a plan is restored onto an empty phone and only then', () async {
    final plan = PlansCompanion.insert(
      id: 'p1',
      startDate: DateTime(2026, 7, 20),
      weeks: 16,
      currentWeeklyM: 40000,
      longestRecentM: 18000,
      daysPerWeek: 5,
      availableWeekdays: '1,2,4,6,7',
      goalDistanceM: const Value(42195),
    );
    await db.restorePlan(
      plan: plan,
      weeks: const <PlanWeeksCompanion>[],
      sessions: const <PlanSessionsCompanion>[],
    );
    expect(await db.hasNoPlan(), isFalse);

    // A second restore must not demote or duplicate what is already here.
    await db.restorePlan(
      plan: plan,
      weeks: const <PlanWeeksCompanion>[],
      sessions: const <PlanSessionsCompanion>[],
    );
    expect(await db.select(db.plans).get(), hasLength(1));
  });
}
