// Regression for EDGE-12: `SupabaseRunBackup.backfill()` read every row off
// `AppDatabase.allRuns()`, which includes a run `RecordingRunRecorder.start`
// began and nothing has finished yet (`endedAt` null is its recovery
// marker, not a run ready to mirror). A run killed mid-recording — before
// launch recovery existed to catch it, or for the one launch between a kill
// and the next app open — got backfilled as 0 m in 0:00, and a restore onto
// another phone brought that back as a finished-looking run that never
// happened. See the throwaway reproduction under
// .claude/worktrees/review-edge/apps/mgk_run/test/zz_edge_review/phantom_run_round_trip_test.dart.
//
// Fake HTTP only, the same technique that reproduction uses; no network.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/history/data/supabase_run_backup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A PostgREST stand-in that remembers what was upserted and answers an
/// empty `runs` select — enough for `backfill` to think the server is empty
/// and try to send everything local.
class _FakeServer {
  final List<Map<String, dynamic>> pushedRuns = <Map<String, dynamic>>[];

  Future<http.Response> handle(http.Request req) async {
    final table = req.url.path.split('/').last;
    if (req.method == 'POST') {
      final body = jsonDecode(req.body);
      final rows = body is List ? body : <dynamic>[body];
      if (table == 'runs') {
        pushedRuns.addAll(rows.map((r) => Map<String, dynamic>.from(r as Map)));
      }
      return http.Response('', 201, request: req);
    }
    // Every select — `runs?select=id`, `run_points`, `run_splits` — answers
    // empty, so the id-diff in `backfill` treats the server as holding
    // nothing yet.
    return http.Response(
      '[]',
      200,
      headers: <String, String>{'content-type': 'application/json'},
      request: req,
    );
  }
}

Future<SupabaseClient> _client(_FakeServer server) async {
  final client = SupabaseClient(
    'https://fake.supabase.co',
    'fake-anon-key',
    httpClient: MockClient(server.handle),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.setInitialSession(
    jsonEncode(<String, dynamic>{
      'access_token': 'not-a-jwt',
      'token_type': 'bearer',
      'user': <String, dynamic>{
        'id': '00000000-0000-0000-0000-000000000001',
        'aud': 'authenticated',
        'created_at': '2026-09-01T00:00:00Z',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
      },
    }),
  );
  return client;
}

void main() {
  test(
    'backfill sends finished runs and leaves an unfinished one alone',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      // Finished: a run stop() completed.
      await db.upsertRun(
        RunsCompanion.insert(
          id: 'finished-run',
          startedAt: DateTime.utc(2026, 9, 20, 7),
          endedAt: Value(DateTime.utc(2026, 9, 20, 8)),
          durationS: 3600,
          distanceM: 10000,
          source: 'gps',
          type: 'outdoor',
        ),
      );
      // Unfinished: `start()` wrote the row and the process died before
      // `stop()` — `endedAt` is still null, the recovery marker.
      await db.upsertRun(
        RunsCompanion.insert(
          id: 'killed-run',
          startedAt: DateTime.utc(2026, 9, 21, 7),
          durationS: 0,
          distanceM: 0,
          source: 'gps',
          type: 'outdoor',
        ),
      );

      final server = _FakeServer();
      final client = await _client(server);
      final sent = await SupabaseRunBackup(db: db, client: client).backfill();

      expect(sent, 1);
      expect(server.pushedRuns.map((r) => r['id']), <String>['finished-run']);
      await db.close();
    },
  );

  test('backfill sends nothing when every local run is unfinished', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.upsertRun(
      RunsCompanion.insert(
        id: 'killed-run',
        startedAt: DateTime.utc(2026, 9, 21, 7),
        durationS: 0,
        distanceM: 0,
        source: 'gps',
        type: 'outdoor',
      ),
    );

    final server = _FakeServer();
    final client = await _client(server);
    final sent = await SupabaseRunBackup(db: db, client: client).backfill();

    expect(sent, 0);
    expect(server.pushedRuns, isEmpty);
    await db.close();
  });
}
