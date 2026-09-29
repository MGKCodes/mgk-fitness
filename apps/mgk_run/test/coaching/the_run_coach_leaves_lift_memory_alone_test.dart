import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_mirror.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_memory.dart';
import 'package:mgk_run/src/features/history/data/supabase_restore.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';

import '../support/fake_postgrest.dart';

/// **This app's coach memory reached into Lift's.**
///
/// The coach's tables hold the whole suite's memory, partitioned by an `app`
/// column on conversations and summaries; turns have none and belong to an
/// app through their conversation. Three places here ignored that:
///
///   * the prune deleted every `coach.turns` row older than 180 days -- Lift's
///     too. Lift numbers a new turn from its row count, so its memory did not
///     just shrink, it froze;
///   * the restore pulled every conversation and every turn, and whichever
///     summary came back first, so a restore imported Lift's memory into this
///     app, which then sent it to the model as this runner's;
///   * the writes named no app and leaned on a column default the migration
///     says to drop once this client names one.
///
/// These run the real mirror and restore against a PostgREST that records
/// what it was asked, and assert on the requests.
void main() {
  late FakePostgrest server;

  setUp(() async => server = await FakePostgrest.start());
  tearDown(() => server.close());

  /// The ids an `in.(...)` filter names.
  List<String> idsIn(String? filter) {
    expect(filter, startsWith('in.('), reason: 'filtered by conversation');
    final inner = filter!.substring(4, filter.length - 1);
    return <String>[for (final id in inner.split(',')) id.replaceAll('"', '')];
  }

  group('the prune', () {
    test(
      "deletes old turns from this app's conversations and no others",
      () async {
        server.rows['conversations'] = <Map<String, Object?>>[
          <String, Object?>{'id': 'run-a'},
          <String, Object?>{'id': 'run-b'},
        ];
        final mirror = SupabaseCoachMemoryMirror(
          client: await server.client(userId: 'alex'),
        );

        await mirror.pushPrune(olderThan: DateTime.utc(2026, 4, 1));

        final read = server.calls.firstWhere(
          (c) => c.method == 'GET' && c.table == 'conversations',
        );
        expect(read.schema, 'coach');
        expect(read.filter('app'), 'eq.run');

        final deletes = server.calls
            .where((c) => c.method == 'DELETE')
            .toList();
        expect(deletes, hasLength(1));
        final delete = deletes.single;
        expect(delete.schema, 'coach');
        expect(delete.table, 'turns');
        expect(idsIn(delete.filter('conversation_id')), <String>[
          'run-a',
          'run-b',
        ]);
        expect(delete.filter('created_at'), startsWith('lt.2026-04-01'));
      },
    );

    test(
      'with no conversations of its own, it deletes nothing at all',
      () async {
        // Not "everything older than the cutoff", which is what an empty filter
        // would have to mean if one were sent.
        final mirror = SupabaseCoachMemoryMirror(
          client: await server.client(userId: 'alex'),
        );

        await mirror.pushPrune(olderThan: DateTime.utc(2026, 4, 1));

        expect(server.calls.where((c) => c.method == 'DELETE'), isEmpty);
      },
    );

    test('a long history is deleted in slices a URL can carry', () async {
      server.rows['conversations'] = <Map<String, Object?>>[
        for (var i = 0; i < 250; i++) <String, Object?>{'id': 'run-$i'},
      ];
      final mirror = SupabaseCoachMemoryMirror(
        client: await server.client(userId: 'alex'),
      );

      await mirror.pushPrune(olderThan: DateTime.utc(2026, 4, 1));

      final deletes = server.calls.where((c) => c.method == 'DELETE').toList();
      expect(deletes, hasLength(3));
      final named = <String>[
        for (final d in deletes) ...idsIn(d.filter('conversation_id')),
      ];
      expect(named, hasLength(250));
      expect(named.toSet(), hasLength(250));
      for (final d in deletes) {
        expect(
          idsIn(d.filter('conversation_id')).length,
          lessThanOrEqualTo(100),
        );
      }
    });
  });

  group('the writes name the app', () {
    test('the summary is this app\'s row', () async {
      final mirror = SupabaseCoachMemoryMirror(
        client: await server.client(userId: 'alex'),
      );

      await mirror.pushSummary(
        CoachSummary(
          text: 'Tight left calf.',
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      );

      final upsert = server.calls.single;
      expect(upsert.table, 'summaries');
      expect((upsert.body! as Map<String, Object?>)['app'], 'run');
    });

    test('and so is the conversation a turn belongs to', () async {
      final mirror = SupabaseCoachMemoryMirror(
        client: await server.client(userId: 'alex'),
      );

      await mirror.pushTurn(
        CoachTurn(
          conversationId: 'run-a',
          seq: 0,
          role: CoachRole.user,
          text: 'My calf is sore.',
          at: DateTime.utc(2026, 9, 1),
        ),
        kind: 'coach',
      );

      final conversation = server.calls.firstWhere(
        (c) => c.table == 'conversations',
      );
      expect((conversation.body! as Map<String, Object?>)['app'], 'run');
    });
  });

  group('the restore', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test("brings back this app's memory, read by this app's name", () async {
      server.rows['summaries'] = <Map<String, Object?>>[
        <String, Object?>{
          'summary': 'Runs before work.',
          'model': null,
          'turns_covered': 2,
          'updated_at': '2026-09-01T00:00:00Z',
        },
      ];
      server.rows['conversations'] = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'run-a',
          'kind': 'coach',
          'started_at': '2026-09-01T07:00:00Z',
          'last_turn_at': '2026-09-01T07:05:00Z',
        },
      ];
      server.rows['turns'] = <Map<String, Object?>>[
        <String, Object?>{
          'conversation_id': 'run-a',
          'seq': 0,
          'role': 'user',
          'body': 'Will not run in the dark.',
          'created_at': '2026-09-01T07:00:00Z',
        },
      ];
      final restore = SupabaseRestore(
        db: db,
        consent: InMemoryBackupConsent(BackupConsent.granted),
        client: await server.client(userId: 'alex'),
      );

      final result = await restore.restoreAll();

      expect(result.turns, 1);
      final summaries = server.calls.firstWhere((c) => c.table == 'summaries');
      expect(summaries.filter('app'), 'eq.run');
      final conversations = server.calls.firstWhere(
        (c) => c.table == 'conversations',
      );
      expect(conversations.filter('app'), 'eq.run');
      final turns = server.calls.where((c) => c.table == 'turns').toList();
      expect(turns, isNotEmpty);
      for (final read in turns) {
        expect(
          idsIn(read.filter('conversation_id')),
          <String>['run-a'],
          reason: 'turns only for the conversations this app restored',
        );
      }
    });

    test('and reads no turns when it has no conversations', () async {
      final restore = SupabaseRestore(
        db: db,
        consent: InMemoryBackupConsent(BackupConsent.granted),
        client: await server.client(userId: 'alex'),
      );

      await restore.restoreAll();

      expect(server.calls.where((c) => c.table == 'turns'), isEmpty);
    });
  });
}
