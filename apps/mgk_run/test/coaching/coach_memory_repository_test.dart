import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_drift_store.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_repository.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_store.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_memory.dart';

/// A mirror that always fails, standing in for a dead network.
///
/// The point of every test using it: the mirror is best-effort, so nothing it
/// does can fail a write or block a read.
class _DeadMirror implements CoachMemoryMirror {
  int attempts = 0;

  @override
  Future<void> pushSummary(CoachSummary summary) async {
    attempts++;
    throw Exception('no network');
  }

  @override
  Future<void> pushTurn(CoachTurn turn, {required String kind}) async {
    attempts++;
    throw Exception('no network');
  }

  @override
  Future<void> pushPrune({required DateTime olderThan}) async {
    attempts++;
    throw Exception('no network');
  }
}

/// Records what it was asked to mirror, so the push contract can be checked
/// without a Supabase client.
class _RecordingMirror implements CoachMemoryMirror {
  final List<CoachSummary> summaries = <CoachSummary>[];
  final List<({CoachTurn turn, String kind})> turns =
      <({CoachTurn turn, String kind})>[];
  final List<DateTime> prunes = <DateTime>[];

  @override
  Future<void> pushSummary(CoachSummary summary) async =>
      summaries.add(summary);

  @override
  Future<void> pushTurn(CoachTurn turn, {required String kind}) async =>
      turns.add((turn: turn, kind: kind));

  @override
  Future<void> pushPrune({required DateTime olderThan}) async =>
      prunes.add(olderThan);
}

/// A stand-in for the semantic search that will one day replace [KeywordRecall]
/// — it exists only to prove the seam holds.
class _AlwaysFirstRecall implements CoachMemoryRecall {
  _AlwaysFirstRecall(this._store);

  final CoachMemoryStore _store;
  int calls = 0;

  @override
  Future<List<CoachTurn>> search(String query, {int limit = 8}) async {
    calls++;
    final turns = await _store.recentTurns();
    return turns.isEmpty ? const <CoachTurn>[] : <CoachTurn>[turns.last];
  }
}

void main() {
  final DateTime t0 = DateTime.utc(2026, 7, 27, 9);
  DateTime clock = t0;
  DateTime now() => clock;

  setUp(() => clock = t0);

  CoachMemoryRepository build({
    CoachMemoryStore? store,
    CoachMemoryMirror? mirror,
    CoachMemoryRecall? recall,
    CoachMemoryRetention retention = CoachMemoryRetention.unboundedForTests,
  }) {
    final s = store ?? InMemoryCoachMemoryStore();
    return CoachMemoryRepository(
      store: s,
      mirror: mirror,
      recall: recall,
      retention: retention,
      now: now,
    );
  }

  group('the rolling summary', () {
    test('replaceSummary stamps the clock and the model', () async {
      final repo = build();
      clock = t0;
      final written = await repo.replaceSummary(
        'Marathon in November, 40k a week.',
        model: 'anthropic/claude-3.5-sonnet',
        turnsCovered: 9,
      );

      expect(written.updatedAt, t0);
      final read = await repo.summary();
      expect(read!.text, 'Marathon in November, 40k a week.');
      expect(read.model, 'anthropic/claude-3.5-sonnet');
      expect(read.turnsCovered, 9);
    });

    test('a regenerated summary replaces the old one', () async {
      final repo = build();
      await repo.replaceSummary('first', model: 'a');
      clock = t0.add(const Duration(days: 7));
      await repo.replaceSummary('second', model: 'b');

      final read = await repo.summary();
      expect(read!.text, 'second');
      expect(read.model, 'b');
      expect(read.updatedAt, t0.add(const Duration(days: 7)));
    });

    test('is null before anything is written', () async {
      expect(await build().summary(), isNull);
    });
  });

  group('the transcript', () {
    test('appended turns read back as a conversation', () async {
      final repo = build();
      await repo.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'my calf has been sore since the half',
      );
      clock = t0.add(const Duration(seconds: 5));
      await repo.appendTurn(
        conversationId: 'c1',
        role: CoachRole.assistant,
        text: 'how sore, and does it settle once you are warm?',
      );

      final turns = await repo.transcript('c1');
      expect(turns, hasLength(2));
      expect(turns.first.isUser, isTrue);
      expect(turns.first.at, t0);
      expect(turns.last.role, CoachRole.assistant);
    });

    test('the turn is on disk before the future completes', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = build(store: DriftCoachMemoryStore(db));

      await repo.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'sore calf',
      );

      // Straight at the table — a force-quit here must keep the turn.
      expect(await db.select(db.coachTurns).get(), hasLength(1));
    });
  });

  group('offline-first', () {
    test('reads never touch the mirror', () async {
      final mirror = _DeadMirror();
      final store = InMemoryCoachMemoryStore();
      await store.saveSummary(
        CoachSummary(text: 'knows me already', updatedAt: t0),
      );
      await store.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'sore calf',
        at: t0,
      );
      final repo = build(store: store, mirror: mirror);

      expect((await repo.summary())!.text, 'knows me already');
      expect(await repo.transcript('c1'), hasLength(1));
      expect(await repo.recall('calf'), hasLength(1));

      // Not "it worked anyway" — it was never asked.
      expect(mirror.attempts, 0);
    });

    test('a write survives a dead mirror', () async {
      final mirror = _DeadMirror();
      final repo = build(
        mirror: mirror,
        retention: const CoachMemoryRetention(),
      );

      await repo.replaceSummary('written offline');
      final turn = await repo.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'written offline too',
      );

      // The mirror was tried and it threw; the local write still stands.
      expect(mirror.attempts, greaterThan(0));
      expect(turn.seq, 0);
      expect((await repo.summary())!.text, 'written offline');
      expect((await repo.transcript('c1')).single.text, 'written offline too');
    });

    test('the mirror is pushed after the local write, with the kind', () async {
      final mirror = _RecordingMirror();
      final repo = build(mirror: mirror);

      await repo.replaceSummary('summary');
      await repo.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'hello',
        kind: 'intake',
      );

      expect(mirror.summaries.single.text, 'summary');
      expect(mirror.turns.single.kind, 'intake');
      expect(mirror.turns.single.turn.remoteId, 'c1-t0');
    });

    test('the remote prune is pushed unconditionally, so it self-heals '
        'after an offline prune', () async {
      // A prune that happened while offline removes nothing locally next time.
      // If the push were conditional on a local removal, the server would keep
      // transcript rows the device erased months ago — permanently.
      final mirror = _RecordingMirror();
      final repo = build(
        mirror: mirror,
        retention: const CoachMemoryRetention(maxAge: Duration(days: 180)),
      );

      await repo.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'one',
      );
      await repo.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'two',
      );

      // Nothing was old enough to prune locally, and it pushed the cutoff both
      // times regardless.
      expect(mirror.prunes, hasLength(2));
      expect(mirror.prunes.first, t0.subtract(const Duration(days: 180)));
    });

    test('no remote prune is pushed when the age bound is disabled', () async {
      final mirror = _RecordingMirror();
      final repo = build(
        mirror: mirror,
        retention: const CoachMemoryRetention(maxAge: null, maxTurns: 10),
      );
      await repo.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'hello',
      );
      expect(mirror.prunes, isEmpty);
    });

    test('no mirror at all is a supported configuration', () async {
      final repo = build(retention: const CoachMemoryRetention());
      await repo.replaceSummary('local only');
      await repo.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'local only',
      );
      expect((await repo.transcript('c1')), hasLength(1));
    });
  });

  group('retention is applied on append', () {
    test('appending past the cap prunes in the same call', () async {
      // Not by a sweep scheduled elsewhere: pruning that only runs if something
      // remembers to schedule it is how a table of health data goes unbounded.
      final repo = build(
        retention: const CoachMemoryRetention(maxAge: null, maxTurns: 3),
      );
      for (var i = 0; i < 6; i++) {
        clock = t0.add(Duration(minutes: i));
        await repo.appendTurn(
          conversationId: 'c1',
          role: CoachRole.user,
          text: 'turn $i',
        );
      }

      final turns = await repo.transcript('c1');
      expect(turns, hasLength(3));
      expect(turns.map((t) => t.text), <String>['turn 3', 'turn 4', 'turn 5']);
    });

    test('the just-appended turn is never the one pruned', () async {
      final repo = build(
        retention: const CoachMemoryRetention(
          maxAge: Duration(days: 1),
          maxTurns: 1,
        ),
      );
      await repo.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'first',
      );
      clock = t0.add(const Duration(days: 900));
      await repo.appendTurn(
        conversationId: 'c1',
        role: CoachRole.user,
        text: 'much later',
      );

      expect((await repo.transcript('c1')).single.text, 'much later');
    });
  });

  group('recall', () {
    Future<CoachMemoryRepository> withTranscript({
      CoachMemoryRecall Function(CoachMemoryStore)? recall,
    }) async {
      final store = InMemoryCoachMemoryStore();
      final lines = <String>[
        'my calf has been sore since the half',
        'I ran 18k on Sunday and felt strong',
        'the calf settled once I was warm',
        'new shoes arrived this week',
      ];
      for (var i = 0; i < lines.length; i++) {
        await store.appendTurn(
          conversationId: 'c1',
          role: CoachRole.user,
          text: lines[i],
          at: t0.add(Duration(minutes: i)),
        );
      }
      return build(store: store, recall: recall?.call(store));
    }

    test('finds the turns that mention the query', () async {
      final repo = await withTranscript();
      final hits = await repo.recall('calf');

      expect(hits, hasLength(2));
      // Equally relevant, so the most recent mention leads.
      expect(hits.first.text, 'the calf settled once I was warm');
    });

    test('ranks a turn matching more terms above one matching fewer', () async {
      final repo = await withTranscript();
      final hits = await repo.recall('sore calf half');
      expect(hits.first.text, 'my calf has been sore since the half');
    });

    test(
      'returns nothing rather than falling back to the most recent',
      () async {
        // "Nothing you said matches" is a real answer, and a useful one — a
        // fallback to recency would feed the coach an irrelevant memory and let
        // it assert something the runner never said.
        final repo = await withTranscript();
        expect(await repo.recall('hamstring'), isEmpty);
      },
    );

    test('a query of only short words matches nothing', () async {
      final repo = await withTranscript();
      expect(await repo.recall('a my is'), isEmpty);
    });

    test('honours the limit', () async {
      final repo = await withTranscript();
      expect(await repo.recall('calf', limit: 1), hasLength(1));
    });

    test(
      'swapping the recall strategy changes nothing for the caller',
      () async {
        // The seam: semantic search replaces this object and nothing else. The
        // caller still says repo.recall(query).
        late _AlwaysFirstRecall swapped;
        final repo = await withTranscript(
          recall: (store) => swapped = _AlwaysFirstRecall(store),
        );

        final hits = await repo.recall('anything at all');

        expect(swapped.calls, 1);
        expect(hits, hasLength(1));
        // The stand-in returns the oldest turn, which the keyword ranker never
        // would for this query — so the swap really took effect.
        expect(hits.single.text, 'my calf has been sore since the half');
      },
    );
  });

  group('a turn never leaks its text', () {
    // CLAUDE.md rule 6. A transcript reaching a log through a stray
    // interpolation is the most likely way this feature leaks health data, and
    // it would not look like a bug in review.
    test('toString reports a length, not the words', () {
      final turn = CoachTurn(
        conversationId: 'c1',
        seq: 0,
        role: CoachRole.user,
        text: 'my calf has been sore since the half',
        at: t0,
      );
      expect(turn.toString(), isNot(contains('calf')));
      expect(turn.toString(), contains('36 chars'));
    });

    test('a store exception names the row, not what was said', () {
      const e = CoachMemoryException('turn c1#0 has unknown role "system"');
      expect(e.toString(), isNot(contains('calf')));
      expect(e.toString(), contains('c1#0'));
    });
  });
}
