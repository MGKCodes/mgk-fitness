import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_drift_store.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_store.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_memory.dart';

/// The coach's memory must survive an app restart, and it must not grow
/// forever. These tests treat "a fresh [DriftCoachMemoryStore] over the same
/// database" as a relaunch — every in-memory object is gone, only rows remain.
///
/// Every behavioural test runs against **both** implementations. The in-memory
/// fake backs the preview harness and most other tests, so a divergence between
/// it and the device store would mean the thing being previewed is not the
/// thing that ships.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// The two implementations, built fresh each time.
  final stores = <String, CoachMemoryStore Function()>{
    'DriftCoachMemoryStore': () => DriftCoachMemoryStore(db),
    'InMemoryCoachMemoryStore': InMemoryCoachMemoryStore.new,
  };

  final DateTime t0 = DateTime.utc(2026, 7, 27, 9);

  stores.forEach((name, build) {
    group('$name — the rolling summary', () {
      test('round trips with its model and timestamp', () async {
        final store = build();
        await store.saveSummary(
          CoachSummary(
            text: 'Training for a November marathon off 40k a week.',
            updatedAt: t0,
            model: 'anthropic/claude-3.5-sonnet',
            turnsCovered: 12,
          ),
        );

        final loaded = await store.loadSummary();
        expect(loaded, isNotNull);
        expect(
          loaded!.text,
          'Training for a November marathon off 40k a week.',
        );
        // The instant, not the representation: Drift stores a DateTime as
        // epoch seconds and hands it back in the local zone, so a UTC literal
        // is the same moment wearing different clothes.
        expect(loaded.updatedAt.isAtSameMomentAs(t0), isTrue);
        // The trace: a summary that turns out to be wrong must name the model
        // and the moment that wrote it, and survive the fix.
        expect(loaded.model, 'anthropic/claude-3.5-sonnet');
        expect(loaded.turnsCovered, 12);
      });

      test('is null before the coach has written one', () async {
        expect(await build().loadSummary(), isNull);
      });

      // The load-bearing invariant of the whole tier.
      test('a second summary REPLACES the first, never accumulates', () async {
        final store = build();
        await store.saveSummary(
          CoachSummary(text: 'first', updatedAt: t0, model: 'model-a'),
        );
        await store.saveSummary(
          CoachSummary(
            text: 'second',
            updatedAt: t0.add(const Duration(days: 1)),
            model: 'model-b',
          ),
        );

        final loaded = await store.loadSummary();
        expect(loaded!.text, 'second');
        expect(loaded.model, 'model-b');
        expect(
          loaded.updatedAt.isAtSameMomentAs(t0.add(const Duration(days: 1))),
          isTrue,
        );
      });

      test('a null model overwrites a known one rather than being '
          'silently dropped', () async {
        // Otherwise a regenerated summary keeps the previous version's
        // attribution, which is worse than no attribution at all.
        final store = build();
        await store.saveSummary(
          CoachSummary(text: 'first', updatedAt: t0, model: 'model-a'),
        );
        await store.saveSummary(CoachSummary(text: 'second', updatedAt: t0));

        expect((await store.loadSummary())!.model, isNull);
      });
    });

    group('$name — the transcript', () {
      test('turns append in order and read back in order', () async {
        final store = build();
        await store.appendTurn(
          conversationId: 'c1',
          role: CoachRole.user,
          text: 'my calf has been sore since the half',
          at: t0,
        );
        await store.appendTurn(
          conversationId: 'c1',
          role: CoachRole.assistant,
          text: 'how long has it been sore?',
          at: t0.add(const Duration(seconds: 4)),
        );

        final turns = await store.loadTurns('c1');
        expect(turns, hasLength(2));
        expect(turns[0].seq, 0);
        expect(turns[0].role, CoachRole.user);
        expect(turns[0].text, 'my calf has been sore since the half');
        expect(turns[1].seq, 1);
        expect(turns[1].role, CoachRole.assistant);
      });

      test('seq is assigned by the store, so callers cannot disagree '
          'about ordering', () async {
        final store = build();
        for (var i = 0; i < 4; i++) {
          final turn = await store.appendTurn(
            conversationId: 'c1',
            role: CoachRole.user,
            text: 'turn $i',
            // Same instant for every turn: ordering must come from seq, not
            // from the clock, because turns can share a tick.
            at: t0,
          );
          expect(turn.seq, i);
        }
        expect((await store.loadTurns('c1')).map((t) => t.text), <String>[
          'turn 0',
          'turn 1',
          'turn 2',
          'turn 3',
        ]);
      });

      test('conversations do not bleed into each other', () async {
        final store = build();
        await store.appendTurn(
          conversationId: 'c1',
          role: CoachRole.user,
          text: 'about my knee',
          at: t0,
        );
        await store.appendTurn(
          conversationId: 'c2',
          role: CoachRole.user,
          text: 'about my shoes',
          at: t0,
        );

        expect(await store.loadTurns('c1'), hasLength(1));
        expect((await store.loadTurns('c1')).single.text, 'about my knee');
        // A new conversation starts its own numbering.
        expect((await store.loadTurns('c2')).single.seq, 0);
      });

      test('an unknown conversation reads as empty, not as an error', () async {
        expect(await build().loadTurns('never-happened'), isEmpty);
      });

      test('recentTurns is newest first, across conversations', () async {
        final store = build();
        await store.appendTurn(
          conversationId: 'c1',
          role: CoachRole.user,
          text: 'oldest',
          at: t0,
        );
        await store.appendTurn(
          conversationId: 'c2',
          role: CoachRole.user,
          text: 'newest',
          at: t0.add(const Duration(hours: 2)),
        );

        final recent = await store.recentTurns();
        expect(recent.map((t) => t.text), <String>['newest', 'oldest']);
        expect((await store.recentTurns(limit: 1)).single.text, 'newest');
      });
    });

    group('$name — retention', () {
      Future<void> seed(CoachMemoryStore store, int count) async {
        for (var i = 0; i < count; i++) {
          await store.appendTurn(
            conversationId: 'c1',
            role: CoachRole.user,
            text: 'turn $i',
            at: t0.add(Duration(minutes: i)),
          );
        }
      }

      test('the count cap keeps the newest N and drops the rest', () async {
        final store = build();
        await seed(store, 5);

        final removed = await store.prune(
          const CoachMemoryRetention(maxAge: null, maxTurns: 3),
          now: t0.add(const Duration(hours: 1)),
        );

        expect(
          removed.map((t) => t.text),
          unorderedEquals(<String>['turn 0', 'turn 1']),
        );
        expect((await store.loadTurns('c1')).map((t) => t.text), <String>[
          'turn 2',
          'turn 3',
          'turn 4',
        ]);
      });

      test('the age window drops turns older than it', () async {
        final store = build();
        await store.appendTurn(
          conversationId: 'c1',
          role: CoachRole.user,
          text: 'ancient',
          at: t0.subtract(const Duration(days: 400)),
        );
        await store.appendTurn(
          conversationId: 'c1',
          role: CoachRole.user,
          text: 'recent',
          at: t0.subtract(const Duration(days: 3)),
        );

        await store.prune(
          const CoachMemoryRetention(maxAge: Duration(days: 180)),
          now: t0,
        );

        expect((await store.loadTurns('c1')).map((t) => t.text), <String>[
          'recent',
        ]);
      });

      test('the turn that triggered the prune always survives', () async {
        // Not by a special case — by construction. The appended turn is the
        // newest, so it clears the cap, and it is stamped `now`, so it cannot
        // be before a cutoff in the past.
        final store = build();
        await seed(store, 3);
        final now = t0.add(const Duration(days: 500));
        final just = await store.appendTurn(
          conversationId: 'c1',
          role: CoachRole.user,
          text: 'the one that ran it',
          at: now,
        );

        await store.prune(
          const CoachMemoryRetention(maxAge: Duration(days: 1), maxTurns: 1),
          now: now,
        );

        final left = await store.loadTurns('c1');
        expect(left, hasLength(1));
        expect(left.single.seq, just.seq);
        expect(left.single.text, 'the one that ran it');
      });

      test('pruning is idempotent — the second run removes nothing', () async {
        final store = build();
        await seed(store, 5);
        const policy = CoachMemoryRetention(maxAge: null, maxTurns: 2);
        final now = t0.add(const Duration(hours: 1));

        expect(await store.prune(policy, now: now), hasLength(3));
        expect(await store.prune(policy, now: now), isEmpty);
        expect(await store.loadTurns('c1'), hasLength(2));
      });

      test('unboundedForTests keeps everything', () async {
        final store = build();
        await seed(store, 5);
        expect(
          await store.prune(
            CoachMemoryRetention.unboundedForTests,
            now: t0.add(const Duration(days: 10000)),
          ),
          isEmpty,
        );
        expect(await store.loadTurns('c1'), hasLength(5));
      });

      test('a conversation pruned to nothing is removed too, not left '
          'as a tombstone', () async {
        final store = build();
        await store.appendTurn(
          conversationId: 'old-chat',
          role: CoachRole.user,
          text: 'ancient',
          at: t0.subtract(const Duration(days: 400)),
        );
        await store.appendTurn(
          conversationId: 'new-chat',
          role: CoachRole.user,
          text: 'recent',
          at: t0,
        );

        await store.prune(
          const CoachMemoryRetention(maxAge: Duration(days: 180)),
          now: t0,
        );

        expect(await store.loadTurns('old-chat'), isEmpty);
        expect(await store.loadTurns('new-chat'), hasLength(1));
      });
    });
  });

  // --- device-specific: durability across a relaunch ---------------------------

  group('DriftCoachMemoryStore — durability', () {
    test('a summary survives a relaunch', () async {
      await DriftCoachMemoryStore(
        db,
      ).saveSummary(CoachSummary(text: 'remembers me', updatedAt: t0));

      // A brand-new store over the same rows, as a relaunch would build.
      final reloaded = await DriftCoachMemoryStore(db).loadSummary();
      expect(reloaded!.text, 'remembers me');
    });

    test('a transcript survives a relaunch', () async {
      await DriftCoachMemoryStore(db).appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'my calf has been sore since the half',
        at: t0,
      );

      final turns = await DriftCoachMemoryStore(db).loadTurns('c1');
      expect(turns.single.text, 'my calf has been sore since the half');
      expect(turns.single.role, CoachRole.user);
    });

    test('replacing the summary leaves exactly one row on disk', () async {
      // The strongest statement of "replaced, never appended": the local table
      // has a constant primary key, so accumulating is not a shape it can take.
      final store = DriftCoachMemoryStore(db);
      for (var i = 0; i < 5; i++) {
        await store.saveSummary(
          CoachSummary(
            text: 'version $i',
            updatedAt: t0.add(Duration(days: i)),
          ),
        );
      }

      expect(await db.select(db.coachSummaries).get(), hasLength(1));
      expect((await store.loadSummary())!.text, 'version 4');
    });

    test('pruned turns are gone from disk, not just from a view', () async {
      final store = DriftCoachMemoryStore(db);
      for (var i = 0; i < 4; i++) {
        await store.appendTurn(
          conversationId: 'c1',
          role: CoachRole.user,
          text: 'turn $i',
          at: t0.add(Duration(minutes: i)),
        );
      }
      await store.prune(
        const CoachMemoryRetention(maxAge: null, maxTurns: 2),
        now: t0.add(const Duration(hours: 1)),
      );

      // Straight at the table: erasure of health data has to be real.
      expect(await db.select(db.coachTurns).get(), hasLength(2));
    });

    test('an unknown role raises rather than being attributed to '
        'the wrong speaker', () async {
      final store = DriftCoachMemoryStore(db);
      await store.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'hello',
        at: t0,
      );
      await db
          .update(db.coachTurns)
          .write(const CoachTurnsCompanion(role: Value('system')));

      await expectLater(
        DriftCoachMemoryStore(db).loadTurns('c1'),
        throwsA(isA<CoachMemoryException>()),
      );
    });

    test('coach memory is additive — an existing run is untouched', () async {
      await db.upsertRun(
        RunsCompanion.insert(
          id: 'run-1',
          startedAt: DateTime.utc(2026, 7, 20, 7),
          durationS: 1800,
          distanceM: 5000,
          source: 'gps',
          type: 'outdoor',
        ),
      );
      await DriftCoachMemoryStore(db).appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'hello',
        at: t0,
      );

      expect(await db.allRuns(), hasLength(1));
    });
  });

  // --- the account-deletion contract -------------------------------------------
  //
  // This group used to live here: it read `supabase/migrations/*.sql` from the
  // Runio repo and regex-parsed it to check that every coach table declared
  // `user_id` (so the deletion sweep would find it), enabled RLS, and revoked
  // UPDATE on the transcript.
  //
  // Those guarantees still matter — more so now the coach is shared by every
  // app in the suite — but this is the wrong place and was always the wrong
  // method. The schema now belongs to the monorepo, and after the 2026-08-06
  // restructure it is built by ALTER ... SET SCHEMA, so no single CREATE TABLE
  // statement states the truth any more. Matching migration text would check a
  // proxy for the schema rather than the schema.
  //
  // They are now pgTAP assertions against the real catalog, which is strictly
  // stronger — they fail if the database is wrong, not merely if the SQL was
  // written differently:
  //
  //     supabase/tests/coach_contract.sql   ->  supabase test db
}
